import Foundation
import Darwin

public struct AgentRequest: Codable, Sendable {
    public let command: String
    public var arguments: [String: String]
    public init(command: String, arguments: [String: String] = [:]) { self.command = command; self.arguments = arguments }
}

// Private per-user Unix socket. No TCP listener, credentials, external service or direct config edits.
public enum AgentTransport {
    public static var directory: String { "/tmp/lynx-\(getuid())" }
    public static var path: String { directory + "/agent.sock" }
    static func address(_ path: String = path) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw AnalysisError.message("本地入口路径过长") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    static func setup(_ fd: Int32) {
        var noSignal: Int32 = 1; _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    static func read(_ fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let n = Darwin.recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                guard n > 0 else { throw AnalysisError.message("App 未响应或连接已结束") }; offset += n
            }
        }; return data
    }
    static func receive(_ fd: Int32) throws -> Data {
        let header = try read(fd, count: 4)
        let size = header.reduce(0) { ($0 << 8) | Int($1) }
        guard size > 0, size <= 8 * 1024 * 1024 else { throw AnalysisError.message("请求或结果过大") }
        return try read(fd, count: size)
    }
    static func send(_ data: Data, fd: Int32) throws {
        guard data.count <= 8 * 1024 * 1024 else { throw AnalysisError.message("请求或结果过大，请按股票查询") }
        var length = UInt32(data.count).bigEndian
        var packet = withUnsafeBytes(of: &length) { Data($0) }; packet.append(data)
        try packet.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let n = Darwin.send(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                guard n > 0 else { throw AnalysisError.message("本地入口写入失败") }; sent += n
            }
        }
    }
    public static func call(_ request: Data, socketPath: String = path) throws -> Data {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AnalysisError.message("无法创建本地连接") }; defer { Darwin.close(fd) }
        setup(fd); var address = try address(socketPath)
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else { throw AnalysisError.message("Lynx 未运行或本地入口不可用，请先打开 App") }
        try send(request, fd: fd); return try receive(fd)
    }
}

public final class AgentServer: @unchecked Sendable {
    private let descriptor: Int32
    private let lock: Int32
    private var source: DispatchSourceRead?
    public init(directory: String = AgentTransport.directory, handler: @escaping @Sendable (Data) async -> Data) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR, (info.st_mode & 0o077) == 0 else {
            throw AnalysisError.message("本地入口目录不属于当前用户或权限不是私有")
        }
        let lockFD = Darwin.open(directory + "/owner.lock", O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw AnalysisError.message("本地入口锁不可用") }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lockFD); throw AnalysisError.message("另一份 Lynx 正在提供 Agent 入口") }
        let listenerFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenerFD >= 0 else { Darwin.close(lockFD); throw AnalysisError.message("本地入口 socket 不可用") }
        unlink(directory + "/agent.sock")
        var address = try AgentTransport.address(directory + "/agent.sock")
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listenerFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0, Darwin.listen(listenerFD, 8) == 0 else { Darwin.close(listenerFD); Darwin.close(lockFD); throw AnalysisError.message("本地入口监听失败") }
        descriptor = listenerFD; lock = lockFD
        let fd = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "Lynx.Agent.Accept"))
        source.setEventHandler {
            let client = Darwin.accept(fd, nil, nil)
            guard client >= 0 else { return }
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { Darwin.close(client); return }
            AgentTransport.setup(client)
            Task.detached {
                defer { Darwin.close(client) }
                do {
                    let input = try AgentTransport.receive(client)
                    let result = await handler(input)
                    try AgentTransport.send(result, fd: client)
                } catch { /* Disconnected clients have no state mutation to replay. */ }
            }
        }
        source.setCancelHandler { Darwin.close(fd) }; source.resume(); self.source = source
    }
    public func stop() { source?.cancel(); source = nil }
    deinit { stop(); Darwin.close(lock) }
}

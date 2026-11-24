import Foundation
import Darwin

// Synchronous, bounded I/O. The adapter is run in a detached task, never on the UI actor.
// A short poll interval also makes cancellation close our own socket promptly.
final class LoopbackSocket {
    private let descriptor: Int32
    private let clock = ContinuousClock()
    private var deadline: ContinuousClock.Instant

    init(port: UInt16, timeout: Duration) throws {
        guard port != 0 else { throw OpenDError.invalidPort }
        deadline = clock.now.advanced(by: timeout)
        descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw OpenDError.transport(errno) }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else { throw OpenDError.transport(errno) }
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw OpenDError.transport(errno)
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw OpenDError.transport(errno) }
            try wait(for: Int16(POLLOUT))
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0 else { throw OpenDError.transport(errno) }
            guard error == 0 else { throw OpenDError.transport(error) }
        }

    }

    // All stored properties are initialized before fallible setup; deinit owns cleanup even if init throws.
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }

    func resetDeadline(timeout: Duration) { deadline = clock.now.advanced(by: timeout) }

    private func wait(for events: Int16) throws {
        while true {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw OpenDError.timeout }
            var descriptor = pollfd(fd: descriptor, events: events, revents: 0)
            let result = poll(&descriptor, 1, 100)
            if result > 0 {
                if descriptor.revents & Int16(POLLNVAL) != 0 { throw OpenDError.closed }
                return // read/write/getsockopt determines the actual EOF or socket error.
            }
            if result < 0 && errno != EINTR { throw OpenDError.transport(errno) }
        }
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                try wait(for: Int16(POLLOUT))
                let count = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
                if count > 0 { sent += count }
                else if count == 0 { throw OpenDError.closed }
                else if errno != EAGAIN && errno != EINTR { throw OpenDError.transport(errno) }
            }
        }
    }

    func read(count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var received = 0
            while received < count {
                try wait(for: Int16(POLLIN))
                let size = Darwin.recv(descriptor, bytes.baseAddress!.advanced(by: received), count - received, 0)
                if size > 0 { received += size }
                else if size == 0 { throw OpenDError.closed }
                else if errno != EAGAIN && errno != EINTR { throw OpenDError.transport(errno) }
            }
        }
        return data
    }
}

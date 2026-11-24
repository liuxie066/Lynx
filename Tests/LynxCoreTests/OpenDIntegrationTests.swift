import Darwin
import Foundation
import Testing
@testable import LynxCore

private final class FakeOpenD: @unchecked Sendable {
    let listener: Int32
    let port: UInt16
    init() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        self.listener = listener
        guard listener >= 0 else { throw OpenDError.transport(errno) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard result == 0, listen(listener, 1) == 0 else { close(listener); throw OpenDError.transport(errno) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }
        guard named == 0 else { close(listener); throw OpenDError.transport(errno) }
        port = UInt16(bigEndian: address.sin_port)
    }
    deinit { close(listener) }

    func serve(_ handler: @escaping @Sendable (Int32) throws -> Void) -> Task<Void, Error> {
        let listener = listener
        return Task.detached {
            var ready = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&ready, 1, 4000) == 1 else { throw OpenDError.timeout }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { throw OpenDError.transport(errno) }
            defer { close(client) }
            var timeout = timeval(tv_sec: 4, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            try handler(client)
        }
    }
}

private func read(_ client: Int32, count: Int) throws -> Data {
    var output = Data()
    while output.count < count {
        var bytes = [UInt8](repeating: 0, count: count - output.count)
        let size = recv(client, &bytes, bytes.count, 0)
        guard size > 0 else { throw OpenDError.closed }
        output.append(contentsOf: bytes.prefix(size))
    }
    return output
}
private func request(_ client: Int32) throws -> OpenDFrame {
    let header = try read(client, count: 44)
    return try OpenDFrame.decode(header: header, body: read(client, count: OpenDFrame.bodyLength(header: header)))
}
private func respond(_ client: Int32, request: OpenDFrame, json: String, wrongNumber: Bool = false) throws {
    let data = try OpenDFrame(protocolID: request.protocolID, sequenceNumber: request.sequenceNumber + (wrongNumber ? 1 : 0), body: Data(json.utf8)).encoded()
    // Deliberate short writes exercise the client's exact-length reads.
    for start in stride(from: 0, to: data.count, by: 7) {
        let part = data.subdata(in: start..<min(start + 7, data.count))
        let written = part.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
        guard written == part.count else { throw OpenDError.closed }
    }
}

@Test func fragmentedHandshakeDiscardsPrivateFields() async throws {
    let server = try FakeOpenD()
    let serving = server.serve { client in
        let req = try request(client)
        #expect(req.protocolID == 1001)
        let json = try #require(JSONSerialization.jsonObject(with: req.body) as? [String: [String: Any]])
        #expect(json["c2s"]?["programmingLanguage"] as? String == "Swift")
        #expect(json["c2s"]?["packetEncAlgo"] as? Int == -1)
        try respond(client, request: req, json: #"{"retType":0,"s2c":{"serverVer":1011,"loginUserID":"PRIVATE","connAESKey":"DO-NOT-RETAIN"}}"#)
    }
    let report = try await OpenDClient(port: server.port).probe()
    #expect(report.serverVersion == 1011)
    #expect(report.snapshots.isEmpty)
    #expect(!String(describing: report).contains("DO-NOT-RETAIN"))
    try await serving.value
}

@Test func protocolRejectionAndResponseMismatch() async throws {
    for wrongNumber in [false, true] {
        let server = try FakeOpenD()
        let serving = server.serve { client in
            try respond(client, request: request(client), json: #"{"retType":-1,"errCode":123,"retMsg":"fixture rejection","s2c":{}}"#, wrongNumber: wrongNumber)
        }
        do { _ = try await OpenDClient(port: server.port).probe(); Issue.record("Expected failure") }
        catch let error as OpenDError {
            #expect(error == (wrongNumber ? .mismatchedResponse : .rejected(protocolID: 1001, code: 123, message: "fixture rejection")))
        }
        try await serving.value
    }
}

@Test func silentServerTimesOutAndCancellationClosesSocket() async throws {
    for cancel in [false, true] {
        let server = try FakeOpenD()
        let serving = server.serve { client in
            _ = try request(client)
            var byte: UInt8 = 0
            #expect(recv(client, &byte, 1, 0) == 0) // Client closes its socket on timeout/cancel.
        }
        let task = Task { try await OpenDClient(port: server.port).probe(timeout: cancel ? .seconds(3) : .milliseconds(150)) }
        if cancel { try await Task.sleep(for: .milliseconds(100)); task.cancel() }
        do { _ = try await task.value; Issue.record("Expected timeout or cancellation") }
        catch is CancellationError { #expect(cancel) }
        catch let error as OpenDError { #expect(!cancel && error == .timeout) }
        try await serving.value
    }
}

@Test func optionProbeUsesOnlyReadOnlyProtocolsAndKeepsUnknowns() async throws {
    let server = try FakeOpenD()
    let serving = server.serve { client in
        let fixtures: [(UInt32, String)] = [
            (1001, #"{"retType":0,"s2c":{"serverVer":1011}}"#),
            (3203, #"{"retType":0,"s2c":{"snapshotList":[{"basic":{"security":{"market":11,"code":"AAPL"},"curPrice":200}}]}}"#),
            (3224, #"{"retType":0,"s2c":{"dateList":[{"strikeTime":"2026-12-18","optionExpiryDateDistance":23}]}}"#),
            (3209, #"{"retType":0,"s2c":{"optionChain":[{"option":[{"call":{"basic":{"security":{"market":11,"code":"CALL"}}},"put":{"basic":{"security":{"market":11,"code":"PUT"}}}}]}]}}"#),
            (3203, #"{"retType":0,"s2c":{"snapshotList":[{"basic":{"security":{"market":11,"code":"PUT"}},"optionExData":{"contractSize":500,"contractMultiplier":500}},{"basic":{"security":{"market":11,"code":"CALL"}},"optionExData":{"contractSize":50,"contractMultiplier":50}}]}}"#)
        ]
        for (expectedID, fixture) in fixtures {
            let req = try request(client)
            #expect(req.protocolID == expectedID)
            try respond(client, request: req, json: fixture)
        }
    }
    let report = try await OpenDClient(port: server.port).probe(.options(market: .us, code: "AAPL"))
    #expect(report.snapshots.count == 3)
    #expect(report.snapshots[1].optionExData?.contractMultiplier == 500)
    #expect(report.snapshots[2].optionExData?.contractMultiplier == 50)
    #expect(report.snapshots[1].optionExData?.openInterest == nil)
    try await serving.value
}

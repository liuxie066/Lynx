import Foundation

public struct QuoteSecurity: Codable, Equatable, Sendable {
    public let market: Int
    public let code: String
    public init(market: Int, code: String) { self.market = market; self.code = code }
}

public struct Snapshot: Decodable, Sendable {
    public struct Basic: Decodable, Sendable {
        public let security: QuoteSecurity
        public let name: String?
        public let curPrice: Double?
        public let bidPrice: Double?
        public let askPrice: Double?
        public let lotSize: Int?
        public let updateTime: String?
        public let priceSpread: Double?
        public let isSuspend: Bool?
        public let secStatus: Int?
        public let type: Int?
    }
    public struct Option: Decodable, Sendable {
        public let owner: QuoteSecurity?
        public let strikeTime: String?
        public let strikePrice: Double?
        public let contractSize: Int?
        public let contractSizeFloat: Double?
        public let contractMultiplier: Double?
        public let ownerLotMultiplier: Double?
        public let openInterest: Int?
        public let delta: Double?
        public let impliedVolatility: Double?
        public let type: Int?
    }
    public let basic: Basic
    public let optionExData: Option?

    public var missingOptionFields: [String] {
        var missing: [String] = []
        if basic.bidPrice == nil { missing.append("bidPrice") }
        if basic.askPrice == nil { missing.append("askPrice") }
        if basic.updateTime == nil { missing.append("updateTime") }
        guard let option = optionExData else { return missing + ["optionExData"] }
        if option.owner == nil { missing.append("owner") }
        if option.strikeTime == nil { missing.append("strikeTime") }
        if option.strikePrice == nil { missing.append("strikePrice") }
        if option.contractSize == nil && option.contractSizeFloat == nil { missing.append("contractSize / contractSizeFloat") }
        if option.contractMultiplier == nil { missing.append("contractMultiplier") }
        if option.ownerLotMultiplier == nil { missing.append("ownerLotMultiplier") }
        if option.openInterest == nil { missing.append("openInterest") }
        if option.delta == nil { missing.append("delta") }
        return missing
    }
}

public struct ProbeReport: Sendable {
    public let checkedAt: Date
    public let serverVersion: Int
    public let snapshots: [Snapshot]
    public let notes: [String]
}

public enum ProbeMode: Sendable {
    case handshake
    case options(market: Market, code: String)
}

public struct OpenDClient: Sendable {
    public let port: UInt16
    public init(port: UInt16 = 11111) { self.port = port }

    // Every run owns a short-lived socket. There is no account or trading API.
    public func probe(_ mode: ProbeMode = .handshake, timeout: Duration = .seconds(20)) async throws -> ProbeReport {
        let worker = Task.detached { try self.run(mode, timeout: timeout) }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private func run(_ mode: ProbeMode, timeout: Duration) throws -> ProbeReport {
        try Task.checkCancellation()
        let requestedOwner: QuoteSecurity?
        switch mode {
        case .handshake: requestedOwner = nil
        case let .options(market, code):
            let stock = try WatchStock(market: market, code: code)
            requestedOwner = QuoteSecurity(market: market.openDCode, code: stock.code)
        }
        let session = try OpenDSession(port: port, timeout: timeout)
        let handshake: HandshakeReply = try session.request(.initialize, HandshakeRequest())
        guard handshake.serverVer > 0 else { throw OpenDError.invalidResponse }
        if case .handshake = mode {
            return ProbeReport(checkedAt: Date(), serverVersion: handshake.serverVer, snapshots: [],
                               notes: ["协议握手成功；尚未验证市场行情权限。短连接已结束。"])
        }
        guard let owner = requestedOwner else { throw OpenDError.invalidResponse }
        let underlying: SnapshotReply = try session.request(.snapshot, SnapshotRequest(securityList: [owner]))
        guard underlying.snapshotList?.count == 1, let spot = underlying.snapshotList?.first, spot.basic.security == owner else { throw OpenDError.invalidResponse }
        let expiries: ExpiryReply = try session.request(.expiration, OwnerRequest(owner: owner))
        guard let expiry = expiries.dateList?.filter({ ($0.optionExpiryDateDistance ?? -1) >= 0 })
            .compactMap(\.strikeTime).sorted().first else {
            return ProbeReport(checkedAt: Date(), serverVersion: handshake.serverVer, snapshots: [spot], notes: ["未返回有效期权到期日；未验证期权行情。"])
        }
        let chain: ChainReply = try session.request(.chain, ChainRequest(owner: owner, beginTime: expiry, endTime: expiry))
        let securities = Array((chain.optionChain ?? []).flatMap { $0.option ?? [] }
            .flatMap { [$0.call?.basic.security, $0.put?.basic.security].compactMap { $0 } }.prefix(2))
        guard !securities.isEmpty else {
            return ProbeReport(checkedAt: Date(), serverVersion: handshake.serverVer, snapshots: [spot], notes: ["最近到期日期权链为空；未验证期权快照。"])
        }
        let quotes: SnapshotReply = try session.request(.snapshot, SnapshotRequest(securityList: securities))
        let values = quotes.snapshotList ?? []
        guard values.count == securities.count, securities.allSatisfy({ security in
            values.filter { $0.basic.security == security }.count == 1
        }) else { throw OpenDError.invalidResponse }
        return ProbeReport(checkedAt: Date(), serverVersion: handshake.serverVer, snapshots: [spot] + values,
                           notes: ["只读样本：一个标的、一个期限、最多两份期权快照。",
                                   "合约规模字段为原始协议值；计算口径与 OM 一致性尚未验证。"])
    }
}

enum QuoteProtocol: UInt32 {
    case keepAlive = 1004, initialize = 1001, snapshot = 3203, chain = 3209, expiration = 3224, history = 3103, calendar = 3219, marketState = 3223, earnings = 3401, staticInfo = 3202
}
struct RequestEnvelope<Body: Encodable>: Encodable { let c2s: Body }
struct ResponseEnvelope<Body: Decodable>: Decodable {
    let retType: Int
    let errCode: Int?
    let retMsg: String?
    let s2c: Body?
    private enum CodingKeys: String, CodingKey { case retType, errCode, retMsg, s2c }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        retType = try container.decode(Int.self, forKey: .retType)
        errCode = try container.decodeIfPresent(Int.self, forKey: .errCode)
        retMsg = try container.decodeIfPresent(String.self, forKey: .retMsg)
        // An error response may have an empty/partial s2c. Preserve its actual error code.
        s2c = retType == 0 ? try container.decodeIfPresent(Body.self, forKey: .s2c) : nil
    }
}
// Only the needed server version is decoded; identity, connection keys and IDs are discarded.
struct HandshakeReply: Decodable { let serverVer: Int }
struct HandshakeRequest: Encodable {
    let clientVer = 300
    let clientID = "Lynx-Swift-Probe"
    let recvNotify = false
    let packetEncAlgo = -1 // Common.PacketEncAlgo_None (0 is legacy encryption)
    let pushProtoFmt = 1
    let programmingLanguage = "Swift"
}
struct SnapshotRequest: Encodable { let securityList: [QuoteSecurity] }
struct SnapshotReply: Decodable { let snapshotList: [Snapshot]? }
struct OwnerRequest: Encodable { let owner: QuoteSecurity }
struct ExpiryReply: Decodable {
    struct Expiry: Decodable { let strikeTime: String?; let optionExpiryDateDistance: Int? }
    let dateList: [Expiry]?
}
struct ChainRequest: Encodable { let owner: QuoteSecurity; let beginTime: String; let endTime: String }
struct ChainReply: Decodable {
    struct StaticInfo: Decodable {
        struct Basic: Decodable { let security: QuoteSecurity; let lotSize: Int?; let secType: Int?; let name: String? }
        struct Option: Decodable { let owner: QuoteSecurity; let strikeTime: String; let strikePrice: Double; let type: Int; let suspend: Bool; let optionStandardType: Int? }
        let basic: Basic
        let optionExData: Option?
    }
    struct Item: Decodable { let call: StaticInfo?; let put: StaticInfo? }
    struct Chain: Decodable { let option: [Item]? }
    let optionChain: [Chain]?
}

final class OpenDSession {
    let socket: LoopbackSocket
    var nextNumber: UInt32 = 1
    init(port: UInt16, timeout: Duration) throws { socket = try LoopbackSocket(port: port, timeout: timeout) }

    func request<Input: Encodable, Output: Decodable>(_ proto: QuoteProtocol, _ input: Input) throws -> Output {
        let number = nextNumber
        nextNumber += 1
        let body = try JSONEncoder().encode(RequestEnvelope(c2s: input))
        try socket.write(OpenDFrame(protocolID: proto.rawValue, sequenceNumber: number, body: body).encoded())
        let header = try socket.read(count: OpenDFrame.headerSize)
        let payload = try socket.read(count: OpenDFrame.bodyLength(header: header))
        let frame = try OpenDFrame.decode(header: header, body: payload)
        guard frame.protocolID == proto.rawValue, frame.sequenceNumber == number else { throw OpenDError.mismatchedResponse }
        let response: ResponseEnvelope<Output>
        do { response = try JSONDecoder().decode(ResponseEnvelope<Output>.self, from: frame.body) }
        catch { throw OpenDError.invalidResponse }
        guard response.retType == 0 else { throw OpenDError.rejected(protocolID: proto.rawValue, code: response.errCode, message: response.retMsg.map { String($0.prefix(500)) }) }
        guard let value = response.s2c else { throw OpenDError.invalidResponse }
        return value
    }
}

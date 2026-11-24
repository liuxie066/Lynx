import Foundation
import CryptoKit

public enum OpenDError: LocalizedError, Equatable {
    case invalidPort, transport(Int32), timeout, closed, malformedFrame, oversizedFrame, checksum
    case mismatchedResponse, invalidResponse, rejected(protocolID: UInt32, code: Int?, message: String? = nil)
    public var errorDescription: String? {
        switch self {
        case .invalidPort: return "OpenD 端口必须为 1–65535。"
        case .transport(let code): return "无法连接本机 OpenD（系统错误 \(code)）。请检查 OpenD 登录状态与端口。"
        case .timeout: return "OpenD 响应超时。请检查连接、登录状态或加密配置。"
        case .closed: return "OpenD 已关闭连接。请检查协议或加密配置。"
        case .malformedFrame: return "OpenD 返回了不支持的协议帧（当前仅支持本机未加密 JSON）。"
        case .oversizedFrame: return "OpenD 响应超过本次验证的大小限制。"
        case .checksum: return "OpenD 响应校验失败，数据未被采用。"
        case .mismatchedResponse: return "OpenD 响应与请求不匹配，数据未被采用。"
        case .invalidResponse: return "OpenD 响应缺少必要字段或格式不兼容。"
        case .rejected(let protocolID, let code, let message): return "OpenD 拒绝请求 \(protocolID)（错误 \(code.map(String.init) ?? "未知")）：\(message ?? "请检查连接与行情权限")"
        }
    }
}

// Independent implementation of the documented 44-byte OpenD header.
// SHA-1 is required by this wire protocol; it is not used as a security primitive.
struct OpenDFrame {
    static let headerSize = 44
    static let maxBodySize = 8 * 1024 * 1024
    let protocolID: UInt32
    let sequenceNumber: UInt32
    let body: Data

    func encoded() throws -> Data {
        guard body.count <= Self.maxBodySize else { throw OpenDError.oversizedFrame }
        var data = Data([0x46, 0x54])
        data.appendLE(protocolID)
        data.append(contentsOf: [1, 0]) // JSON, protocol version 0
        data.appendLE(sequenceNumber)
        data.appendLE(UInt32(body.count))
        data.append(contentsOf: Insecure.SHA1.hash(data: body))
        data.append(Data(repeating: 0, count: 8))
        data.append(body)
        return data
    }

    static func bodyLength(header: Data) throws -> Int {
        guard header.count == headerSize, Array(header.prefix(2)) == [0x46, 0x54], header[6] == 1, header[7] == 0 else {
            throw OpenDError.malformedFrame
        }
        let count = Int(header.uint32LE(at: 12))
        guard count <= maxBodySize else { throw OpenDError.oversizedFrame }
        return count
    }

    static func decode(header: Data, body: Data) throws -> Self {
        guard try bodyLength(header: header) == body.count else { throw OpenDError.malformedFrame }
        guard Data(Insecure.SHA1.hash(data: body)) == header.subdata(in: 16..<36) else { throw OpenDError.checksum }
        return Self(protocolID: header.uint32LE(at: 2), sequenceNumber: header.uint32LE(at: 8), body: body)
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    func uint32LE(at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(self[offset + $1]) << ($1 * 8) }
    }
}

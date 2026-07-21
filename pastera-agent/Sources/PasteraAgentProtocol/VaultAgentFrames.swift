import Foundation

public struct VaultAgentClientHello: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let publicKey: Data
    public let nonce: Data

    public init(protocolVersion: Int, publicKey: Data, nonce: Data) {
        self.protocolVersion = protocolVersion
        self.publicKey = publicKey
        self.nonce = nonce
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let publicKey = try values.decode(Data.self, forKey: .publicKey)
        let nonce = try values.decode(Data.self, forKey: .nonce)
        try validateHandshake(publicKey: publicKey, nonce: nonce)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        self.publicKey = publicKey
        self.nonce = nonce
    }
}

public struct VaultAgentServerHello: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let connectionID: UUID
    public let publicKey: Data
    public let nonce: Data

    public init(protocolVersion: Int, connectionID: UUID, publicKey: Data, nonce: Data) {
        self.protocolVersion = protocolVersion
        self.connectionID = connectionID
        self.publicKey = publicKey
        self.nonce = nonce
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let publicKey = try values.decode(Data.self, forKey: .publicKey)
        let nonce = try values.decode(Data.self, forKey: .nonce)
        try validateHandshake(publicKey: publicKey, nonce: nonce)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        connectionID = try values.decode(UUID.self, forKey: .connectionID)
        self.publicKey = publicKey
        self.nonce = nonce
    }
}

public struct VaultAgentEncryptedFrame: Codable, Equatable, Sendable {
    public let connectionID: UUID
    public let sequence: UInt64
    public let ciphertext: Data

    public init(connectionID: UUID, sequence: UInt64, ciphertext: Data) {
        self.connectionID = connectionID
        self.sequence = sequence
        self.ciphertext = ciphertext
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let ciphertext = try values.decode(Data.self, forKey: .ciphertext)
        guard ciphertext.count <= VaultAgentLimits.maximumFrameBytes else {
            throw VaultAgentProtocolError.limitExceeded
        }
        connectionID = try values.decode(UUID.self, forKey: .connectionID)
        sequence = try values.decode(UInt64.self, forKey: .sequence)
        self.ciphertext = ciphertext
    }
}

public enum VaultAgentFrameCodec {
    public static func frame(payload: Data) throws -> Data {
        let maximumPayloadBytes = VaultAgentLimits.maximumFrameBytes - MemoryLayout<UInt32>.size
        guard payload.count <= maximumPayloadBytes else {
            throw VaultAgentProtocolError.frameTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + payload
    }

    public static func payload(from frame: Data) throws -> Data {
        guard frame.count >= MemoryLayout<UInt32>.size else {
            throw VaultAgentProtocolError.malformedFrame
        }
        guard frame.count <= VaultAgentLimits.maximumFrameBytes else {
            throw VaultAgentProtocolError.frameTooLarge
        }
        let declared = frame.prefix(4).reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        let maximumPayloadBytes = VaultAgentLimits.maximumFrameBytes - MemoryLayout<UInt32>.size
        guard Int(declared) <= maximumPayloadBytes else {
            throw VaultAgentProtocolError.frameTooLarge
        }
        guard frame.count == Int(declared) + 4 else {
            throw VaultAgentProtocolError.malformedFrame
        }
        return frame.dropFirst(4)
    }
}

private func validateHandshake(publicKey: Data, nonce: Data) throws {
    guard publicKey.count == VaultAgentLimits.publicKeyBytes,
          nonce.count == VaultAgentLimits.nonceBytes else {
        throw VaultAgentProtocolError.limitExceeded
    }
}

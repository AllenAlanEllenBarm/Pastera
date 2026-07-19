import Foundation
import Testing
@testable import PasteraAgentProtocol

@Suite("Vault agent protocol")
struct VaultAgentProtocolTests {
    @Test("metadata schema cannot encode notes or passwords")
    func metadataSchemaCannotEncodeSecrets() throws {
        let value = VaultAgentEntryMetadata(
            id: UUID(),
            folderID: UUID(),
            folderName: "Work",
            title: "Mail",
            website: "https://example.test",
            username: "alice",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let json = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        #expect(!json.localizedCaseInsensitiveContains("password"))
        #expect(!json.localizedCaseInsensitiveContains("note"))
    }

    @Test("frame codec rejects payloads above the fixed limit")
    func frameCodecRejectsOversizedPayload() {
        let bytes = Data(repeating: 0x41, count: VaultAgentLimits.maximumFrameBytes + 1)
        #expect(throws: VaultAgentProtocolError.frameTooLarge) {
            try VaultAgentFrameCodec.frame(payload: bytes)
        }
    }

    @Test("operation uses stable type and payload keys")
    func operationUsesStableWireKeys() throws {
        let operation = VaultAgentOperation.prepareExec(
            entryID: UUID(),
            field: .password,
            mode: .fileDescriptor
        )

        let data = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "prepare_exec")
        #expect(object["payload"] != nil)
        #expect(try JSONDecoder().decode(VaultAgentOperation.self, from: data) == operation)
    }

    @Test("decoded requests enforce query and page limits")
    func decodedRequestsEnforceLimits() throws {
        let value = String(repeating: "q", count: VaultAgentLimits.maximumQueryBytes + 1)
        let data = try JSONSerialization.data(withJSONObject: [
            "query": value,
            "limit": 1
        ])

        #expect(throws: VaultAgentProtocolError.limitExceeded) {
            try JSONDecoder().decode(VaultAgentSearchRequest.self, from: data)
        }
    }

    @Test("response body encodes one stable branch")
    func responseBodyEncodesOneStableBranch() throws {
        let value = VaultAgentResponseBody.failure(.init(
            code: .entryNotFound,
            message: "Missing",
            retryable: false,
            retryAfterMilliseconds: nil
        ))

        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "failure")
        #expect(object["payload"] != nil)
        #expect(object["data"] == nil)
        #expect(object["error"] == nil)
    }

    @Test("decoded handshakes require exact key material lengths")
    func decodedHandshakesRequireExactKeyMaterialLengths() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": VaultAgentLimits.protocolVersion,
            "publicKey": Data(repeating: 0, count: VaultAgentLimits.publicKeyBytes - 1).base64EncodedString(),
            "nonce": Data(repeating: 0, count: VaultAgentLimits.nonceBytes).base64EncodedString()
        ])

        #expect(throws: VaultAgentProtocolError.limitExceeded) {
            try JSONDecoder().decode(VaultAgentClientHello.self, from: data)
        }
    }

    @Test("decoded enum values use the protocol invalid-value error")
    func decodedEnumValuesUseProtocolInvalidValueError() throws {
        let data = try JSONEncoder().encode("unknown-host")

        #expect(throws: VaultAgentProtocolError.invalidValue) {
            try JSONDecoder().decode(VaultAgentHostKind.self, from: data)
        }
    }

    @Test("response envelopes reject JSON encodings above the response limit")
    func responseEnvelopesRejectOversizedEncodings() throws {
        let entry = VaultAgentEntryMetadata(
            id: UUID(),
            folderID: UUID(),
            folderName: String(repeating: "f", count: VaultAgentLimits.maximumMetadataFieldBytes),
            title: String(repeating: "t", count: VaultAgentLimits.maximumMetadataFieldBytes),
            website: String(repeating: "w", count: VaultAgentLimits.maximumMetadataFieldBytes),
            username: String(repeating: "u", count: VaultAgentLimits.maximumMetadataFieldBytes),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let response = VaultAgentResponseEnvelope(
            protocolVersion: VaultAgentLimits.protocolVersion,
            connectionID: UUID(),
            sequence: 1,
            requestID: UUID(),
            body: .success(.search(.init(entries: Array(repeating: entry, count: VaultAgentLimits.maximumPageSize), nextCursor: nil)))
        )

        #expect(throws: VaultAgentProtocolError.limitExceeded) {
            try JSONEncoder().encode(response)
        }
    }
}

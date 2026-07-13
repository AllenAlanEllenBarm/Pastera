import Foundation
import Testing
@testable import Pastera

@Suite("Secure clipboard")
struct SecureClipboardServiceTests {
    @Test("copy registers one-time history suppression")
    func copyRegistersSuppression() {
        let pasteboard = TestSecretPasteboard()
        var ignoredChangeCounts = [Int]()
        let service = SecureClipboardService(
            pasteboard: pasteboard,
            suppressHistoryChange: { ignoredChangeCounts.append($0) },
            schedule: { _, _ in }
        )

        service.copySecret("secret-value", clearAfter: .seconds(60))

        #expect(pasteboard.string == "secret-value")
        #expect(ignoredChangeCounts == [pasteboard.changeCount])
    }

    @Test("timer clears only an unchanged secret")
    func timerClearsOnlyUnchangedSecret() throws {
        let pasteboard = TestSecretPasteboard()
        var scheduled: (() -> Void)?
        let service = SecureClipboardService(
            pasteboard: pasteboard,
            suppressHistoryChange: { _ in },
            schedule: { _, action in scheduled = action }
        )
        service.copySecret("secret-value", clearAfter: .seconds(60))

        let action = try #require(scheduled)
        action()

        #expect(pasteboard.string == nil)
    }

    @Test("timer preserves content copied later")
    func timerPreservesReplacementContent() throws {
        let pasteboard = TestSecretPasteboard()
        var scheduled: (() -> Void)?
        let service = SecureClipboardService(
            pasteboard: pasteboard,
            suppressHistoryChange: { _ in },
            schedule: { _, action in scheduled = action }
        )
        service.copySecret("secret-value", clearAfter: .seconds(60))
        pasteboard.writeString("replacement")

        let action = try #require(scheduled)
        action()

        #expect(pasteboard.string == "replacement")
    }

    @Test("clip service consumes ignored change once")
    func clipServiceConsumesIgnoredChangeOnce() {
        let service = ClipService()
        service.ignorePasteboardChange(42)

        #expect(service.consumeIgnoredPasteboardChangeForTesting(42))
        #expect(!service.consumeIgnoredPasteboardChangeForTesting(42))
    }
}

private final class TestSecretPasteboard: SecretPasteboard {
    private(set) var changeCount = 0
    private(set) var string: String?

    func writeString(_ value: String) {
        string = value
        changeCount += 1
    }

    func clear() {
        string = nil
        changeCount += 1
    }
}

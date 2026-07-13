import AppKit
import Foundation

protocol SecureClipboardWriting {
    func copySecret(_ secret: String, clearAfter: Duration)
}

protocol SecretPasteboard: AnyObject {
    var changeCount: Int { get }
    func writeString(_ value: String)
    func clear()
}

final class SecureClipboardService: SecureClipboardWriting {
    typealias Scheduler = (Duration, @escaping () -> Void) -> Void

    private let pasteboard: SecretPasteboard
    private let suppressHistoryChange: (Int) -> Void
    private let schedule: Scheduler

    init(
        pasteboard: SecretPasteboard = SystemSecretPasteboard(),
        suppressHistoryChange: @escaping (Int) -> Void = { AppEnvironment.current.clipService.ignorePasteboardChange($0) },
        schedule: @escaping Scheduler = SecureClipboardService.scheduleOnMainQueue
    ) {
        self.pasteboard = pasteboard
        self.suppressHistoryChange = suppressHistoryChange
        self.schedule = schedule
    }

    func copySecret(_ secret: String, clearAfter duration: Duration) {
        pasteboard.writeString(secret)
        let protectedChangeCount = pasteboard.changeCount
        suppressHistoryChange(protectedChangeCount)
        schedule(duration) { [weak pasteboard] in
            guard let pasteboard, pasteboard.changeCount == protectedChangeCount else { return }
            pasteboard.clear()
            self.suppressHistoryChange(pasteboard.changeCount)
        }
    }

    private static func scheduleOnMainQueue(_ duration: Duration, action: @escaping () -> Void) {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }
}

private final class SystemSecretPasteboard: SecretPasteboard {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    func writeString(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    func clear() {
        pasteboard.clearContents()
    }
}

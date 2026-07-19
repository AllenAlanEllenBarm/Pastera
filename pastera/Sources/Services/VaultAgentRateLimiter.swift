import Foundation
import PasteraAgentProtocol

enum VaultAgentRateLimitCategory: CaseIterable, Hashable {
    case metadata
    case directSecret
    case ticket

    var limit: Int {
        switch self {
        case .metadata: 60
        case .directSecret, .ticket: 10
        }
    }
}

struct VaultAgentRateLimitError: Error, Equatable {
    let retryAfterMilliseconds: Int
}

final class VaultAgentRateLimiter {
    private struct BucketKey: Hashable {
        let client: VaultAgentClientKind
        let category: VaultAgentRateLimitCategory
    }

    private static let window: TimeInterval = 60
    private let lock = NSLock()
    private var buckets: [BucketKey: [Date]]

    init() {
        var buckets = [BucketKey: [Date]]()
        for client in VaultAgentClientKind.allCases {
            for category in VaultAgentRateLimitCategory.allCases {
                buckets[BucketKey(client: client, category: category)] = []
            }
        }
        self.buckets = buckets
    }

    func check(
        client: VaultAgentClientKind,
        category: VaultAgentRateLimitCategory,
        at date: Date
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let key = BucketKey(client: client, category: category)
        let cutoff = date.addingTimeInterval(-Self.window)
        var timestamps = buckets[key, default: []]
        timestamps.removeAll { $0 <= cutoff }
        if timestamps.count >= category.limit, let oldest = timestamps.min() {
            buckets[key] = timestamps
            let remaining = oldest.addingTimeInterval(Self.window).timeIntervalSince(date)
            let milliseconds = min(60_000, max(1, Int(ceil(remaining * 1_000))))
            throw VaultAgentRateLimitError(retryAfterMilliseconds: milliseconds)
        }
        timestamps.append(date)
        buckets[key] = timestamps
    }
}

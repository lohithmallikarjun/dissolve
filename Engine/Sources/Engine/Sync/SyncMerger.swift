import Foundation

/// Last-writer-wins merging, per record.
public enum SyncMerger {
    /// Picks the changes to apply: per record, the newest of the batch, and only if newer
    /// than what was last applied. Tombstones win like any other change, so an older edit
    /// can't bring a deleted record back. Updates `versions` with the winners.
    public static func merge(_ incoming: [ChangeRecord], into versions: inout [RecordKey: RecordVersion]) -> [ChangeRecord] {
        var newest: [RecordKey: ChangeRecord] = [:]
        for record in incoming {
            if let existing = newest[record.key], existing.version >= record.version { continue }
            newest[record.key] = record
        }
        var winners: [ChangeRecord] = []
        for (key, record) in newest {
            if let current = versions[key], current >= record.version { continue }
            versions[key] = record.version
            winners.append(record)
        }
        return winners.sorted { $0.updatedAt < $1.updatedAt }
    }

    /// One record per key — the newest, tombstones included. Used for monthly snapshots.
    public static func compact(_ records: [ChangeRecord]) -> [ChangeRecord] {
        var versions: [RecordKey: RecordVersion] = [:]
        return merge(records, into: &versions)
    }
}

/// Timestamps for local edits.
public enum SyncClock {
    /// `now`, unless the record was last changed "in the future" (a device whose clock runs ahead):
    /// then just after that, so an edit made after seeing a change always supersedes it.
    public static func stamp(now: Date = Date(), previous: Date?) -> Date {
        let now = SyncTime.rounded(now)
        guard let previous, previous >= now else { return now }
        return SyncTime.rounded(previous.addingTimeInterval(0.001))
    }
}

/// Stable UUIDs for records that must be the same on every device, e.g. one habit log per
/// habit per day: both devices derive the same ID, so their edits merge instead of duplicating.
public enum DeterministicID {
    public static func uuid(for name: String) -> UUID {
        // Two FNV-1a 64-bit hashes with different offsets → 128 bits.
        var h1: UInt64 = 0xcbf2_9ce4_8422_2325
        var h2: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in name.utf8 {
            h1 = (h1 ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            h2 = (h2 ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            h2 = h2 &+ (h2 << 7)
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: h1 >> (8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: h2 >> (8 * i))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5-style
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

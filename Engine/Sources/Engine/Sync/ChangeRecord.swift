import Foundation

/// One line of a device's change log: `{entity, id, updatedAt, deleted, fields}`.
public struct ChangeRecord: Codable, Hashable, Sendable {
    public var entity: String
    public var id: UUID
    public var updatedAt: Date
    public var deleted: Bool
    /// The device that made the change; breaks exact `updatedAt` ties deterministically.
    public var device: String
    /// The entity's fields. nil for deletes (tombstones).
    public var fields: JSONValue?

    public init(entity: String, id: UUID, updatedAt: Date, deleted: Bool = false, device: String, fields: JSONValue?) {
        self.entity = entity
        self.id = id
        self.updatedAt = SyncTime.rounded(updatedAt)
        self.deleted = deleted
        self.device = device
        self.fields = deleted ? nil : fields
    }

    public var key: RecordKey { RecordKey(entity: entity, id: id) }
    public var version: RecordVersion { RecordVersion(updatedAt: updatedAt, device: device, deleted: deleted) }
}

public struct RecordKey: Hashable, Codable, Sendable {
    public var entity: String
    public var id: UUID

    public init(entity: String, id: UUID) {
        self.entity = entity
        self.id = id
    }
}

/// What the receiver remembers about the last applied change of a record (including tombstones).
public struct RecordVersion: Hashable, Codable, Sendable, Comparable {
    public var updatedAt: Date
    public var device: String
    public var deleted: Bool

    public init(updatedAt: Date, device: String, deleted: Bool) {
        self.updatedAt = updatedAt
        self.device = device
        self.deleted = deleted
    }

    /// Newest `updatedAt` wins; an exact tie goes to the larger device ID so every device agrees.
    public static func < (lhs: RecordVersion, rhs: RecordVersion) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.device < rhs.device
    }
}

/// Reads and writes JSON-lines change logs.
public enum ChangeLog {
    public static func line(for record: ChangeRecord) throws -> Data {
        var data = try JSONEncoder.syncFields.encode(record)
        data.append(0x0A)
        return data
    }

    public static func lines(for records: [ChangeRecord]) throws -> Data {
        try records.reduce(into: Data()) { $0.append(try line(for: $1)) }
    }

    /// Parses complete lines starting at byte `offset`. A trailing line without a newline
    /// (still being written or synced) is left for next time. Malformed lines are skipped.
    /// Returns the records and the offset to resume from.
    public static func parse(_ data: Data, from offset: Int = 0) -> (records: [ChangeRecord], nextOffset: Int, skipped: Int) {
        guard offset < data.count else { return ([], max(offset, 0) > data.count ? data.count : offset, 0) }
        var records: [ChangeRecord] = []
        var skipped = 0
        var start = offset
        var cursor = offset
        let decoder = JSONDecoder.syncFields
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            while cursor < buffer.count {
                if buffer[cursor] == 0x0A {
                    if cursor > start {
                        let slice = data.subdata(in: start..<cursor)
                        if let record = try? decoder.decode(ChangeRecord.self, from: slice) {
                            records.append(record)
                        } else {
                            skipped += 1
                        }
                    }
                    start = cursor + 1
                }
                cursor += 1
            }
        }
        return (records, start, skipped)
    }
}

import Foundation
import Testing
@testable import Engine

/// Two devices syncing through append-only per-device logs, like the iCloud Drive folder.
private struct Device {
    let name: String
    /// This device's own log file.
    var log = Data()
    /// Last applied version per record.
    var versions: [RecordKey: RecordVersion] = [:]
    /// The local "database": record → value.
    var values: [RecordKey: Double] = [:]
    /// How far we've read each other device's log.
    var cursors: [String: Int] = [:]
    var clockSkew: TimeInterval = 0

    mutating func edit(_ id: UUID, value: Double, at time: Date) throws {
        let key = RecordKey(entity: "habitLog", id: id)
        let stamp = SyncClock.stamp(now: time.addingTimeInterval(clockSkew), previous: versions[key]?.updatedAt)
        let record = ChangeRecord(entity: "habitLog", id: id, updatedAt: stamp, device: name,
                                  fields: .object(["value": .number(value)]))
        values[key] = value
        _ = SyncMerger.merge([record], into: &versions)
        log.append(try ChangeLog.line(for: record))
    }

    mutating func delete(_ id: UUID, at time: Date) throws {
        let key = RecordKey(entity: "habitLog", id: id)
        let stamp = SyncClock.stamp(now: time.addingTimeInterval(clockSkew), previous: versions[key]?.updatedAt)
        let record = ChangeRecord(entity: "habitLog", id: id, updatedAt: stamp, deleted: true, device: name, fields: nil)
        values[key] = nil
        _ = SyncMerger.merge([record], into: &versions)
        log.append(try ChangeLog.line(for: record))
    }

    /// Reads another device's log (possibly only partly synced) from the saved offset.
    mutating func pull(from other: Device, visibleBytes: Int? = nil) {
        let data = other.log.prefix(visibleBytes ?? other.log.count)
        let parsed = ChangeLog.parse(Data(data), from: cursors[other.name] ?? 0)
        cursors[other.name] = parsed.nextOffset
        for record in SyncMerger.merge(parsed.records, into: &versions) {
            values[record.key] = record.deleted ? nil : record.fields?["value"]?.doubleValue
        }
    }
}

@Suite("Sync: two devices")
struct SyncSimulationTests {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    let waterToday = DeterministicID.uuid(for: "habitLog|water|2026-10-15")
    let readToday = DeterministicID.uuid(for: "habitLog|read|2026-10-15")

    @Test func bothDevicesConvergeAfterOfflineEdits() throws {
        var phone = Device(name: "phone"), mac = Device(name: "mac")
        // Both offline: phone logs 3 glasses, mac logs 5 a minute later; phone also logs reading.
        try phone.edit(waterToday, value: 3, at: t0)
        try mac.edit(waterToday, value: 5, at: t0.addingTimeInterval(60))
        try phone.edit(readToday, value: 20, at: t0.addingTimeInterval(90))
        phone.pull(from: mac)
        mac.pull(from: phone)
        #expect(phone.values == mac.values)
        #expect(phone.values[RecordKey(entity: "habitLog", id: waterToday)] == 5)
        #expect(phone.values[RecordKey(entity: "habitLog", id: readToday)] == 20)
    }

    @Test func deletePropagatesAndStaysDeleted() throws {
        var phone = Device(name: "phone"), mac = Device(name: "mac")
        try phone.edit(waterToday, value: 2, at: t0)
        mac.pull(from: phone)
        try mac.delete(waterToday, at: t0.addingTimeInterval(10))
        phone.pull(from: mac)
        #expect(phone.values.isEmpty && mac.values.isEmpty)
        // Pulling again (or re-reading old lines) doesn't bring it back.
        phone.cursors = [:]
        phone.pull(from: mac)
        mac.pull(from: phone)
        #expect(phone.values.isEmpty && mac.values.isEmpty)
    }

    @Test func halfSyncedLineIsPickedUpLater() throws {
        var phone = Device(name: "phone"), mac = Device(name: "mac")
        try mac.edit(waterToday, value: 4, at: t0)
        try mac.edit(readToday, value: 15, at: t0.addingTimeInterval(1))
        phone.pull(from: mac, visibleBytes: mac.log.count - 20)  // iCloud has delivered part of it
        #expect(phone.values.count == 1)
        phone.pull(from: mac)
        #expect(phone.values == mac.values)
    }

    @Test func fastClockOnOneDeviceDoesNotFreezeTheRecord() throws {
        var phone = Device(name: "phone"), mac = Device(name: "mac", clockSkew: 600)  // Mac 10 min ahead
        try mac.edit(waterToday, value: 6, at: t0)
        phone.pull(from: mac)
        // The phone edits right after (true time t0+30 s, earlier than the Mac's stamp).
        try phone.edit(waterToday, value: 7, at: t0.addingTimeInterval(30))
        mac.pull(from: phone)
        #expect(mac.values[RecordKey(entity: "habitLog", id: waterToday)] == 7)
        #expect(phone.values == mac.values)
    }
}

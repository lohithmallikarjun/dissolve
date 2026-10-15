import Foundation
import Testing
@testable import Engine

private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

private struct LogDTO: Codable, Equatable {
    var habitID: UUID
    var date: String
    var value: Double
    var note: String
    var createdAt: Date
}

private func record(_ id: UUID, _ seconds: Double, device: String, value: Double = 1, deleted: Bool = false) -> ChangeRecord {
    ChangeRecord(entity: "habitLog", id: id, updatedAt: at(seconds), deleted: deleted, device: device,
                 fields: .object(["value": .number(value)]))
}

@Suite("Sync: change log format")
struct ChangeLogTests {
    @Test func lineRoundTripsWithFields() throws {
        let dto = LogDTO(habitID: UUID(), date: "2026-10-15", value: 3, note: "a \"quoted\" note\nwith a newline",
                         createdAt: SyncTime.rounded(at(0.123)))
        let r = ChangeRecord(entity: "habitLog", id: UUID(), updatedAt: at(1.5), device: "A", fields: try JSONValue(encoding: dto))
        let data = try ChangeLog.line(for: r)
        #expect(data.last == 0x0A)
        #expect(data.dropLast().contains(0x0A) == false)  // one physical line, even with a newline in the note
        let parsed = ChangeLog.parse(data)
        #expect(parsed.records == [r])
        #expect(try parsed.records[0].fields!.decode(LogDTO.self) == dto)
    }

    @Test func tombstonesCarryNoFields() {
        let r = ChangeRecord(entity: "habit", id: UUID(), updatedAt: t0, deleted: true, device: "A", fields: .string("x"))
        #expect(r.fields == nil)
    }

    @Test func resumesFromOffsetAndLeavesPartialLine() throws {
        let a = record(UUID(), 1, device: "A"), b = record(UUID(), 2, device: "A"), c = record(UUID(), 3, device: "A")
        var data = try ChangeLog.lines(for: [a, b])
        let first = ChangeLog.parse(data)
        #expect(first.records == [a, b])
        #expect(first.nextOffset == data.count)

        // c arrives half-synced: no trailing newline yet.
        let cLine = try ChangeLog.line(for: c)
        data.append(cLine.dropLast(10))
        let second = ChangeLog.parse(data, from: first.nextOffset)
        #expect(second.records.isEmpty)
        #expect(second.nextOffset == first.nextOffset)

        // The rest arrives.
        data = try ChangeLog.lines(for: [a, b, c])
        let third = ChangeLog.parse(data, from: second.nextOffset)
        #expect(third.records == [c])
        #expect(third.nextOffset == data.count)
    }

    @Test func skipsMalformedLines() throws {
        let a = record(UUID(), 1, device: "A")
        var data = Data("not json\n".utf8)
        data.append(try ChangeLog.line(for: a))
        data.append(Data("{\"entity\":1}\n".utf8))
        let parsed = ChangeLog.parse(data)
        #expect(parsed.records == [a])
        #expect(parsed.skipped == 2)
    }

    @Test func offsetPastEndIsSafe() {
        let parsed = ChangeLog.parse(Data("abc".utf8), from: 10)
        #expect(parsed.records.isEmpty)
        #expect(parsed.nextOffset <= 10)
    }
}

@Suite("Sync: merging")
struct MergeTests {
    @Test func newestWinsWhenTwoDevicesEditTheSameDay() {
        // Both devices derive the same ID for "Water on 2026-10-15".
        let id = DeterministicID.uuid(for: "habit-1|2026-10-15")
        let phone = record(id, 10, device: "phone", value: 3)
        let mac = record(id, 20, device: "mac", value: 5)
        var versions: [RecordKey: RecordVersion] = [:]
        #expect(SyncMerger.merge([phone, mac], into: &versions) == [mac])
        // Order of arrival doesn't matter.
        var versions2: [RecordKey: RecordVersion] = [:]
        _ = SyncMerger.merge([mac], into: &versions2)
        #expect(SyncMerger.merge([phone], into: &versions2).isEmpty)
        #expect(versions == versions2)
    }

    @Test func exactTieIsDeterministic() {
        let id = UUID()
        let a = record(id, 10, device: "A", value: 1)
        let b = record(id, 10, device: "B", value: 2)
        var v1: [RecordKey: RecordVersion] = [:], v2: [RecordKey: RecordVersion] = [:]
        #expect(SyncMerger.merge([a, b], into: &v1) == [b])
        _ = SyncMerger.merge([b], into: &v2)
        #expect(SyncMerger.merge([a], into: &v2).isEmpty)
    }

    @Test func deleteIsATombstone() {
        let id = UUID()
        let edit = record(id, 10, device: "A")
        let delete = record(id, 20, device: "B", deleted: true)
        let staleEdit = record(id, 15, device: "A", value: 9)
        var versions: [RecordKey: RecordVersion] = [:]
        _ = SyncMerger.merge([edit], into: &versions)
        #expect(SyncMerger.merge([delete], into: &versions) == [delete])
        // An older edit arriving late can't resurrect it.
        #expect(SyncMerger.merge([staleEdit], into: &versions).isEmpty)
        #expect(versions[delete.key]?.deleted == true)
        // A genuinely newer edit (re-created) does win.
        let recreate = record(id, 30, device: "A")
        #expect(SyncMerger.merge([recreate], into: &versions) == [recreate])
    }

    @Test func reapplyingIsIdempotent() {
        let r = record(UUID(), 10, device: "A")
        var versions: [RecordKey: RecordVersion] = [:]
        #expect(SyncMerger.merge([r], into: &versions).count == 1)
        #expect(SyncMerger.merge([r], into: &versions).isEmpty)
    }

    @Test func entitiesDoNotCollide() {
        let id = UUID()
        let habit = ChangeRecord(entity: "habit", id: id, updatedAt: at(1), device: "A", fields: .null)
        let log = ChangeRecord(entity: "habitLog", id: id, updatedAt: at(1), device: "A", fields: .null)
        var versions: [RecordKey: RecordVersion] = [:]
        #expect(SyncMerger.merge([habit, log], into: &versions).count == 2)
    }

    @Test func compactKeepsNewestPerRecordIncludingTombstones() {
        let a = UUID(), b = UUID()
        let records = [record(a, 1, device: "A", value: 1), record(a, 3, device: "A", value: 3),
                       record(b, 2, device: "A"), record(b, 4, device: "A", deleted: true)]
        let compacted = SyncMerger.compact(records)
        #expect(compacted.count == 2)
        #expect(compacted.first { $0.id == a }?.fields?["value"] == .number(3))
        #expect(compacted.first { $0.id == b }?.deleted == true)
    }
}

@Suite("Sync: clocks and IDs")
struct ClockTests {
    @Test func stampUsesNowNormally() {
        #expect(SyncClock.stamp(now: at(100), previous: at(50)) == at(100))
        #expect(SyncClock.stamp(now: at(100.0004), previous: nil) == SyncTime.rounded(at(100.0004)))
        #expect(SyncClock.stamp(now: at(100), previous: nil) == at(100))
    }

    @Test func editAfterSeeingAFastClockStillWins() {
        // The Mac's clock is 5 minutes ahead: its change is stamped t=400.
        // The iPhone (true time t=200) edits after receiving it; its stamp must still be newer.
        let macChange = at(400)
        let phoneStamp = SyncClock.stamp(now: at(200), previous: macChange)
        #expect(phoneStamp > macChange)
        let id = UUID()
        var versions: [RecordKey: RecordVersion] = [:]
        _ = SyncMerger.merge([record(id, 400, device: "mac")], into: &versions)
        let phoneEdit = ChangeRecord(entity: "habitLog", id: id, updatedAt: phoneStamp, device: "phone", fields: .null)
        #expect(SyncMerger.merge([phoneEdit], into: &versions) == [phoneEdit])
    }

    @Test func deterministicIDsAreStableAndDistinct() {
        let a = DeterministicID.uuid(for: "habit-1|2026-10-15")
        #expect(a == DeterministicID.uuid(for: "habit-1|2026-10-15"))
        #expect(a != DeterministicID.uuid(for: "habit-1|2026-10-16"))
        #expect(a != DeterministicID.uuid(for: "habit-2|2026-10-15"))
        #expect(a.uuidString.dropFirst(14).first == "5")  // version nibble
        var seen = Set<UUID>()
        for i in 0..<10_000 { seen.insert(DeterministicID.uuid(for: "journal|\(i)")) }
        #expect(seen.count == 10_000)
    }
}

@Suite("Journal")
struct JournalTests {
    private func d(_ s: String) -> LocalDate { LocalDate(s)! }

    @Test func streakAllowsTodayToBeOpen() {
        let dates: Set<LocalDate> = [d("2026-10-12"), d("2026-10-13"), d("2026-10-14")]
        #expect(JournalStats.streak(entryDates: dates, today: d("2026-10-15")) == 3)
        #expect(JournalStats.streak(entryDates: dates.union([d("2026-10-15")]), today: d("2026-10-15")) == 4)
        #expect(JournalStats.streak(entryDates: dates, today: d("2026-10-16")) == 0)
        #expect(JournalStats.streak(entryDates: [], today: d("2026-10-16")) == 0)
    }

    @Test(arguments: [("", 0), ("Hello", 1), ("Hello, world!", 2), ("  it's well-being  ", 2),
                      ("one\ntwo\tthree", 3), ("a - b", 2), ("Ran 5 km 🏃", 3), ("café naïve", 2)])
    func wordCount(_ text: String, _ expected: Int) {
        #expect(JournalStats.wordCount(text) == expected)
    }

    @Test func onThisDay() {
        let dates = [d("2024-10-15"), d("2025-10-15"), d("2025-10-14"), d("2026-10-15")]
        #expect(JournalStats.onThisDay(dates, today: d("2026-10-15")) == [d("2025-10-15"), d("2024-10-15")])
    }
}

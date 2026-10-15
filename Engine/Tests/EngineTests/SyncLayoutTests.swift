import Foundation
import Testing
@testable import Engine

@Suite("SyncLayout")
struct SyncLayoutTests {
    @Test func changeLogIsPerDevicePerMonth() {
        let path = SyncLayout.changeLogPath(deviceID: "ABC", month: LocalDate("2026-03-07")!)
        #expect(path == "changes/ABC/2026-03.jsonl")
    }

    @Test func photoPaths() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        #expect(SyncLayout.photoPath(id: id) == "photos/11111111-2222-3333-4444-555555555555.heic")
        #expect(SyncLayout.thumbnailPath(id: id) == "photos/11111111-2222-3333-4444-555555555555_thumb.heic")
    }

    @Test func diagnosticPath() {
        #expect(SyncLayout.diagnosticPath(deviceID: "XYZ") == "m0/XYZ.json")
    }

    @Test func placeholderNames() {
        #expect(SyncLayout.realName(forPlaceholder: ".XYZ.json.icloud") == "XYZ.json")
        #expect(SyncLayout.realName(forPlaceholder: "XYZ.json") == nil)
        #expect(SyncLayout.realName(forPlaceholder: ".icloud") == nil)
        #expect(SyncLayout.realName(forPlaceholder: ".DS_Store") == nil)
    }
}

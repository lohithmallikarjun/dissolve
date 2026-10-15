import Foundation
import SwiftData

/// Milestone 0 only: proves the app and widget share one SwiftData store.
@Model
final class DiagnosticPing {
    var id: UUID
    var value: Int
    var deviceName: String
    var updatedAt: Date

    init(value: Int, deviceName: String, updatedAt: Date = .now) {
        id = UUID()
        self.value = value
        self.deviceName = deviceName
        self.updatedAt = updatedAt
    }
}

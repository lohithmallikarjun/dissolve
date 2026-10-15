import Foundation
import SwiftData

/// Where the SwiftData store ended up, shown on the Milestone 0 screen.
struct StoreStatus: Sendable {
    let usesAppGroup: Bool
    let failure: String?

    static let preview = StoreStatus(usesAppGroup: true, failure: nil)
}

/// Builds the one SwiftData store, in the App Group container so the
/// widgets read the same data. Local only: CloudKit is explicitly off.
enum SharedModelContainer {
    static var schema: Schema { Schema([DiagnosticPing.self]) }
    private static let storeName = "Dissolve"

    static func appGroup() throws -> ModelContainer {
        let config = ModelConfiguration(
            storeName, schema: schema,
            groupContainer: .identifier(AppGroup.id),
            cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// The app's container. Falls back to the app's own sandbox if the
    /// App Group is unavailable, so the app still opens and can report it.
    static func make() -> (ModelContainer, StoreStatus) {
        var failure: String?
        if AppGroup.containerURL != nil {
            do {
                return (try appGroup(), StoreStatus(usesAppGroup: true, failure: nil))
            } catch {
                failure = error.localizedDescription
            }
        } else {
            failure = "App Group container not available"
        }
        let local = ModelConfiguration(
            storeName, schema: schema, groupContainer: .none, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: local)
            return (container, StoreStatus(usesAppGroup: false, failure: failure))
        } catch {
            fatalError("Could not open the SwiftData store: \(error)")
        }
    }

    static func inMemory() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: config)
    }
}

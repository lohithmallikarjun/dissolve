import SwiftData
import SwiftUI

@main
struct DissolveApp: App {
    private let container: ModelContainer
    private let storeStatus: StoreStatus
    @State private var syncFolder = SyncFolderStore()

    init() {
        let made = SharedModelContainer.make()
        container = made.0
        storeStatus = made.1
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeStatus: storeStatus)
                .environment(syncFolder)
                .tint(.green)
        }
        .modelContainer(container)
    }
}

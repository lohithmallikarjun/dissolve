import SwiftData
import SwiftUI

/// Milestone 0: a single diagnostics screen. Tabs (iPhone) and the
/// sidebar (Mac) arrive in Milestone 1.
struct RootView: View {
    let storeStatus: StoreStatus

    var body: some View {
        NavigationStack {
            DiagnosticsView(storeStatus: storeStatus)
        }
    }
}

#Preview {
    RootView(storeStatus: .preview)
        .environment(SyncFolderStore(defaults: UserDefaults(suiteName: "preview")!))
        .modelContainer(SharedModelContainer.inMemory())
}

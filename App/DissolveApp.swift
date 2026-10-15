import SwiftData
import SwiftUI

@main
struct DissolveApp: App {
    @State private var container: ModelContainer
    private let storeStatus: StoreStatus
    @State private var loadedAt = Date.now.timeIntervalSince1970
    @State private var syncFolder = SyncFolderStore()
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS) && DEBUG
    @NSApplicationDelegateAdaptor(LaunchDiagnostics.self) private var launchDiagnostics
    #endif

    init() {
        let made = SharedModelContainer.make()
        _container = State(initialValue: made.0)
        storeStatus = made.1
        #if DEBUG
        DemoData.seedIfRequested(in: made.0.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeStatus: storeStatus)
                .environment(syncFolder)
                .environment(model)
                .tint(.green)
                .onAppear { print("Dissolve: root view appeared") }
                .task { await model.runDayClock() }
                #if DEBUG
                .task { await WidgetGallery.renderIfRequested(container: container) }
                #endif
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.refreshToday()
            reloadIfChangedElsewhere()
        }
        .commands {
            DissolveCommands(model: model)
        }

        #if os(macOS)
        Settings {
            NavigationStack { SettingsView(storeStatus: storeStatus) }
                .environment(syncFolder)
                .modelContainer(container)
                .frame(width: 460, height: 520)
        }
        #endif
    }
}

extension DissolveApp {
    /// Widgets log habits from their own process; reopen the store so the app shows those changes.
    private func reloadIfChangedElsewhere() {
        let changedAt = AppGroup.defaults.double(forKey: SharedKeys.externalChangeAt)
        guard changedAt > loadedAt else { return }
        loadedAt = Date.now.timeIntervalSince1970
        container = SharedModelContainer.make().0
    }
}

/// ⌘1–4 switch sections, ⌘← / ⌘→ change day.
struct DissolveCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Go") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.title) {
                    model.section = section
                    model.selectedHabitID = nil
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("Previous Day") { model.moveDay(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next Day") { model.moveDay(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(model.day >= model.today)
            Button("Go to Today") { model.showDay(model.today) }
                .keyboardShortcut("t", modifiers: .command)
        }
    }
}

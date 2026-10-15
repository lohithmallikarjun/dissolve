import AppIntents
import SwiftData
import SwiftUI
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

@main
struct DissolveApp: App {
    static let refreshTaskID = "com.lohith.dissolve.sync"

    @State private var container: ModelContainer
    private let storeStatus: StoreStatus
    @State private var loadedAt = Date.now.timeIntervalSince1970
    @State private var syncFolder: SyncFolderStore
    @State private var sync: SyncService
    @State private var model = AppModel()
    @State private var journalLock = JournalLock()
    @Environment(\.scenePhase) private var scenePhase
    private let notificationHandler = NotificationHandler()
    #if os(macOS) && DEBUG
    @NSApplicationDelegateAdaptor(LaunchDiagnostics.self) private var launchDiagnostics
    #endif

    init() {
        let made = SharedModelContainer.make()
        // Every save goes through Persistence.save, which records changes for sync.
        made.0.mainContext.autosaveEnabled = false
        _container = State(initialValue: made.0)
        storeStatus = made.1
        let folder = SyncFolderStore()
        _syncFolder = State(initialValue: folder)
        _sync = State(initialValue: SyncService(folderStore: folder))
        #if DEBUG
        DemoData.seedIfRequested(in: made.0.mainContext)
        #endif
        UNUserNotificationCenter.current().delegate = notificationHandler
        ReminderService.registerCategories()
        DissolveShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeStatus: storeStatus)
                .environment(syncFolder)
                .environment(sync)
                .environment(model)
                .environment(journalLock)
                .tint(.green)
                .onOpenURL { model.handle($0) }
                .task { await model.runDayClock() }
                .task { await sync.sync(container: container) }
                #if os(macOS)
                .task { await periodicSync() }
                #endif
                .onReceive(NotificationCenter.default.publisher(for: .dissolveLocalChange)) { _ in
                    sync.syncSoon(container: container)
                    Task { await ReminderService.reschedule(container: container) }
                }
                .onChange(of: syncFolder.folderURL) { _, url in
                    if url != nil { Task { await sync.sync(container: container) } }
                }
                #if DEBUG
                .task { await WidgetGallery.renderIfRequested(container: container) }
                #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.refreshToday()
                reloadIfChangedElsewhere()
                if let url = AppSettings.pendingURL {
                    AppSettings.pendingURL = nil
                    model.handle(url)
                }
                Task {
                    await sync.sync(container: container)
                    await ReminderService.reschedule(container: container)
                }
            case .background:
                journalLock.lock()
                #if os(iOS)
                scheduleBackgroundSync()
                #endif
            default:
                break
            }
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await scheduleBackgroundSync()
            await sync.sync(container: container)
        }
        #endif
        .commands {
            DissolveCommands(model: model)
        }

        #if os(macOS)
        Settings {
            NavigationStack { SettingsView(storeStatus: storeStatus) }
                .environment(syncFolder)
                .environment(sync)
                .environment(journalLock)
                .modelContainer(container)
                .frame(width: 480, height: 600)
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
        let fresh = SharedModelContainer.make().0
        fresh.mainContext.autosaveEnabled = false
        container = fresh
    }

    #if os(iOS)
    /// Asks iOS to wake the app roughly hourly to merge other devices' changes.
    private func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif

    #if os(macOS)
    private func periodicSync() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10 * 60))
            await sync.sync(container: container)
        }
    }
    #endif
}

/// ⌘N new journal entry, ⌘1–4 switch sections, ⌘← / ⌘→ change day.
struct DissolveCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Journal Entry") { model.openJournal() }
                .keyboardShortcut("n", modifiers: .command)
        }
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

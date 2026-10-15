import SwiftData
import SwiftUI

/// iPhone: tabs. Mac: sidebar with sections, then habits, then templates.
struct RootView: View {
    let storeStatus: StoreStatus
    @Environment(AppModel.self) private var model
    @Environment(SyncFolderStore.self) private var syncFolder
    @AppStorage("sync.setupDismissed") private var setupDismissed = false
    @State private var showingSyncSetup = false

    var body: some View {
        Group {
            #if os(macOS)
            MacRootView(storeStatus: storeStatus)
            #else
            PhoneRootView(storeStatus: storeStatus)
            #endif
        }
        .sheet(isPresented: $showingSyncSetup) {
            SyncSetupView { setupDismissed = true }
        }
        .task {
            // First launch: ask for the shared iCloud Drive folder (skipped for CI screenshots).
            let isCI = ProcessInfo.processInfo.arguments.contains("-demoData")
            if syncFolder.folderURL == nil, !setupDismissed, !isCI { showingSyncSetup = true }
        }
    }
}

#if os(iOS)
private struct PhoneRootView: View {
    let storeStatus: StoreStatus
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.section) {
            Tab(AppSection.today.title, systemImage: AppSection.today.symbol, value: .today) {
                NavigationStack { TodayView().toolbar { settingsButton } }
            }
            Tab(AppSection.progress.title, systemImage: AppSection.progress.symbol, value: .progress) {
                NavigationStack { ProgressScreen().toolbar { settingsButton } }
            }
            Tab(AppSection.journal.title, systemImage: AppSection.journal.symbol, value: .journal) {
                NavigationStack { JournalView().toolbar { settingsButton } }
            }
            Tab(AppSection.life.title, systemImage: AppSection.life.symbol, value: .life) {
                NavigationStack { LifeView().toolbar { settingsButton } }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(storeStatus: storeStatus)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { showingSettings = true }
        }
    }
}
#endif

#if os(macOS)
private enum SidebarItem: Hashable {
    case section(AppSection)
    case habit(UUID)
    case template
}

private struct MacRootView: View {
    let storeStatus: StoreStatus
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Habit> { $0.archivedAt == nil }, sort: \Habit.sortOrder) private var habits: [Habit]

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { model.selectedHabitID.map(SidebarItem.habit) ?? .section(model.section) },
            set: { item in
                switch item {
                case .section(let section):
                    model.section = section
                    model.selectedHabitID = nil
                case .habit(let id):
                    model.selectedHabitID = id
                case .template, nil:
                    break
                }
            })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section == .life ? String(localized: "Life & Countdowns") : section.title,
                              systemImage: section.symbol)
                            .tag(SidebarItem.section(section))
                    }
                }
                Section("Habits") {
                    ForEach(habits) { habit in
                        Label {
                            Text(habit.name)
                        } icon: {
                            Circle().fill(habit.color).frame(width: 9, height: 9)
                        }
                        .tag(SidebarItem.habit(habit.id))
                    }
                }
                Section("Templates") {
                    Label("Daily Journal", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.template)
                        .help("More templates arrive in Milestone 7")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack {
                detail
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedHabitID, let habit = habits.first(where: { $0.id == id }) {
            HabitDetailView(habit: habit)
        } else {
            switch model.section {
            case .today: TodayView()
            case .progress: ProgressScreen()
            case .journal: JournalView()
            case .life: LifeView()
            }
        }
    }
}
#endif

#Preview {
    let folder = SyncFolderStore(defaults: UserDefaults(suiteName: "preview")!)
    RootView(storeStatus: .preview)
        .environment(AppModel())
        .environment(JournalLock())
        .environment(SyncService(folderStore: folder))
        .environment(folder)
        .modelContainer(PreviewData.container)
}

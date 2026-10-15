import SwiftData
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers
import WidgetKit

struct SettingsView: View {
    let storeStatus: StoreStatus

    @Environment(\.modelContext) private var context
    @Environment(SyncFolderStore.self) private var syncFolder
    @Environment(SyncService.self) private var sync
    @Environment(JournalLock.self) private var journalLock
    @Query(filter: #Predicate<Habit> { $0.archivedAt != nil }, sort: \Habit.name) private var archived: [Habit]
    @State private var dayEndsAt = AppSettings.dayEndsAtHour
    @State private var pickingFolder = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var journalNudge = AppSettings.journalNudgeMinutes != nil
    @State private var nudgeTime = Calendar.current.date(
        from: DateComponents(hour: (AppSettings.journalNudgeMinutes ?? 1290) / 60,
                             minute: (AppSettings.journalNudgeMinutes ?? 1290) % 60)) ?? .now

    var body: some View {
        @Bindable var journalLock = journalLock
        Form {
            Section {
                LabeledContent("Folder", value: syncFolder.folderName ?? String(localized: "Not set up"))
                if let date = sync.lastSyncedAt {
                    LabeledContent("Last sync") {
                        Text("\(Text(date, style: .relative)) ago")
                    }
                    Text(sync.lastSummary).font(.caption).foregroundStyle(.secondary)
                }
                if let error = sync.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if syncFolder.folderURL != nil {
                    Button(sync.isSyncing ? "Syncing…" : "Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await sync.sync(container: context.container) }
                    }
                    .disabled(sync.isSyncing)
                }
                Button(syncFolder.folderURL == nil ? "Choose iCloud Drive Folder…" : "Change Folder…",
                       systemImage: "folder") { pickingFolder = true }
            } header: {
                Text("Sync")
            } footer: {
                Text("Pick the same iCloud Drive folder on your iPhone and Mac.")
            }

            Section {
                switch notificationStatus {
                case .authorized, .provisional:
                    Label("Notifications on", systemImage: "bell.badge.fill").foregroundStyle(.green)
                case .denied:
                    Label("Notifications are off for Dissolve in system Settings", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                default:
                    Button("Allow Notifications", systemImage: "bell") {
                        Task {
                            _ = await ReminderService.requestPermission()
                            await refreshNotifications()
                        }
                    }
                }
                Toggle("Evening journal nudge", isOn: $journalNudge)
                if journalNudge {
                    DatePicker("Time", selection: $nudgeTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Habit reminders are set per habit (Edit Habit → Remind me). The journal nudge skips days you've already written.")
            }
            .onChange(of: journalNudge) { saveNudge() }
            .onChange(of: nudgeTime) { saveNudge() }

            Section {
                Toggle("Lock with \(journalLock.biometryName)", isOn: $journalLock.isEnabled)
            } header: {
                Text("Journal")
            } footer: {
                Text("The journal locks whenever Dissolve leaves the screen, and is blurred in the app switcher.")
            }

            Section {
                Picker("Day ends at", selection: $dayEndsAt) {
                    Text("Midnight").tag(0)
                    ForEach(1..<6) { hour in
                        Text(Calendar.current.date(from: DateComponents(hour: hour))!
                            .formatted(date: .omitted, time: .shortened)).tag(hour)
                    }
                }
                .onChange(of: dayEndsAt) { _, hour in
                    AppSettings.dayEndsAtHour = hour
                    WidgetCenter.shared.reloadAllTimelines()
                }
            } footer: {
                Text("A check-off before this time counts for the previous day.")
            }

            Section("Archived habits") {
                if archived.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
                ForEach(archived) { habit in
                    HStack {
                        Image(systemName: habit.symbol).foregroundStyle(habit.color)
                        Text(habit.name)
                        Spacer()
                        Button("Unarchive") {
                            habit.archivedAt = nil
                            habit.updatedAt = .now
                            HabitActions.save(context)
                        }
                    }
                }
            }

            Section {
                NavigationLink("Milestone 0 checks") {
                    DiagnosticsView(storeStatus: storeStatus)
                }
            } footer: {
                Text("App Group, widget and iCloud Drive folder tests.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { syncFolder.select($0) }
        .task { await refreshNotifications() }
    }

    private func refreshNotifications() async {
        notificationStatus = await ReminderService.authorizationStatus()
    }

    private func saveNudge() {
        let time = Calendar.current.dateComponents([.hour, .minute], from: nudgeTime)
        AppSettings.journalNudgeMinutes = journalNudge ? (time.hour ?? 21) * 60 + (time.minute ?? 30) : nil
        Task { await ReminderService.reschedule(container: context.container) }
    }
}

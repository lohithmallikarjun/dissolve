import SwiftData
import SwiftUI
import WidgetKit

struct SettingsView: View {
    let storeStatus: StoreStatus

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { $0.archivedAt != nil }, sort: \Habit.name) private var archived: [Habit]
    @State private var dayEndsAt = AppSettings.dayEndsAtHour

    var body: some View {
        Form {
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
    }
}

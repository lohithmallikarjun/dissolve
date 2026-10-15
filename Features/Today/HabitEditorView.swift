import Engine
import SwiftData
import SwiftUI

/// Create or edit a habit. A schedule change takes effect from a chosen date,
/// so earlier days are still judged by the old schedule.
struct HabitEditorView: View {
    let habit: Habit?
    let nextSortOrder: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = "checkmark"
    @State private var colorName = HabitColor.green.rawValue
    @State private var kind: HabitKind = .binary
    @State private var target: Double = 1
    @State private var unit = ""
    @State private var scheduleKind: HabitSchedule.Kind = .daily
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var timesPerWeek = 3
    @State private var everyNDays = 2
    @State private var startDate = Date.now
    @State private var scheduleFrom = Date.now
    @State private var remind = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 8)) ?? .now
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var isNew: Bool { habit == nil }

    private var rule: ScheduleRule {
        switch scheduleKind {
        case .daily: .daily
        case .weekdays: .weekdays(weekdays)
        case .timesPerWeek: .timesPerWeek(timesPerWeek)
        case .everyNDays: .everyNDays(everyNDays)
        }
    }

    private var scheduleChanged: Bool {
        guard let habit else { return false }
        return habit.rule(on: AppSettings.today()) != rule
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !(scheduleKind == .weekdays && weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. Meditate"))
                        .font(.title3)
                }

                Section("Look") {
                    symbolPicker
                    colorPicker
                }

                Section {
                    Picker("Type", selection: $kind) {
                        Text("Yes / No").tag(HabitKind.binary)
                        Text("Amount").tag(HabitKind.quantity)
                        Text("Minutes").tag(HabitKind.timed)
                        Text("Limit").tag(HabitKind.limit)
                    }
                    .pickerStyle(.segmented)
                    if kind != .binary {
                        HStack {
                            Text(kind == .limit ? "At most" : "Goal")
                            Spacer()
                            TextField("Target", value: $target, format: .number.precision(.fractionLength(0...1)))
                                .multilineTextAlignment(.trailing)
                                .numberStyle()
                                .frame(maxWidth: 80)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Stepper("Target", value: $target, in: 0...10_000, step: kind == .timed ? 5 : 1)
                                .labelsHidden()
                        }
                        if kind != .timed {
                            TextField("Unit", text: $unit, prompt: Text(kind == .limit ? "e.g. coffees" : "e.g. glasses"))
                        }
                    }
                } header: {
                    Text("Type")
                } footer: {
                    Text(kindFooter)
                }

                Section("Schedule") {
                    Picker("Repeat", selection: $scheduleKind) {
                        Text("Every day").tag(HabitSchedule.Kind.daily)
                        Text("Specific days").tag(HabitSchedule.Kind.weekdays)
                        Text("Times per week").tag(HabitSchedule.Kind.timesPerWeek)
                        Text("Every few days").tag(HabitSchedule.Kind.everyNDays)
                    }
                    switch scheduleKind {
                    case .daily:
                        EmptyView()
                    case .weekdays:
                        WeekdayChips(selection: $weekdays)
                    case .timesPerWeek:
                        Stepper("\(timesPerWeek)× a week", value: $timesPerWeek, in: 1...7)
                            .numberStyle()
                    case .everyNDays:
                        Stepper("Every \(everyNDays) days", value: $everyNDays, in: 2...60)
                            .numberStyle()
                    }
                    if isNew {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    } else if scheduleChanged {
                        DatePicker("New schedule from", selection: $scheduleFrom, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("Remind me", isOn: $remind.animation(.snappy))
                    if remind {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Only on days it's due, and not once it's done.")
                }

                if let habit {
                    Section {
                        Button(habit.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                            habit.archivedAt = habit.isArchived ? nil : .now
                            habit.updatedAt = .now
                            HabitActions.save(context)
                            dismiss()
                        }
                        Button("Delete Habit", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                    } footer: {
                        Text("Archived habits leave Today and the widgets but keep their history.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New Habit" : "Edit Habit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete “\(name)” and all its history?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let habit { context.delete(habit) }
                    HabitActions.save(context)
                    dismiss()
                }
            } message: {
                Text("Archive it instead to keep the history.")
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 560)
        #endif
    }

    private var kindFooter: LocalizedStringKey {
        switch kind {
        case .binary: "Done or not done."
        case .quantity: "Partial progress counts towards the grid."
        case .timed: "Minutes spent; each tap adds 5."
        case .limit: "Success means staying at or under the limit."
        }
    }

    private var symbolPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(HabitSymbols.all, id: \.self) { name in
                Button {
                    withAnimation(.snappy) { symbol = name }
                } label: {
                    Image(systemName: name)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(symbol == name ? .white : HabitColor.named(colorName).color)
                        .background(symbol == name ? HabitColor.named(colorName).color : Color.primary.opacity(0.06),
                                    in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(symbol == name ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(HabitColor.allCases) { color in
                Button {
                    withAnimation(.snappy) { colorName = color.rawValue }
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if colorName == color.rawValue {
                                Circle().strokeBorder(.white, lineWidth: 3).padding(3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.name))
                .accessibilityAddTraits(colorName == color.rawValue ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let habit else { return }
        name = habit.name
        symbol = habit.symbol
        colorName = habit.colorName
        kind = habit.kind
        target = habit.target
        unit = habit.unit
        if let minutes = habit.reminderMinutes {
            remind = true
            reminderTime = Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? reminderTime
        }
        switch habit.rule(on: AppSettings.today()) {
        case .daily: scheduleKind = .daily
        case .weekdays(let days): scheduleKind = .weekdays; weekdays = days
        case .timesPerWeek(let n): scheduleKind = .timesPerWeek; timesPerWeek = n
        case .everyNDays(let n): scheduleKind = .everyNDays; everyNDays = n
        }
    }

    private func save() {
        let dayEnds = AppSettings.dayEndsAtHour
        let target = kind == .binary ? 1 : max(target, kind == .limit ? 0 : 1)
        let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let reminderMinutes = remind ? (time.hour ?? 8) * 60 + (time.minute ?? 0) : nil
        if remind { Task { _ = await ReminderService.requestPermission() } }
        if let habit {
            habit.name = name.trimmingCharacters(in: .whitespaces)
            habit.symbol = symbol
            habit.colorName = colorName
            habit.kind = kind
            habit.target = target
            habit.unit = unit
            habit.reminderMinutes = reminderMinutes
            habit.updatedAt = .now
            if scheduleChanged {
                let from = max(LocalDate(scheduleFrom, dayEndsAtHour: 0), habit.localStartDate)
                if let same = habit.schedules.first(where: { $0.effectiveFrom == from.description }) {
                    same.rule = rule
                } else {
                    let schedule = HabitSchedule(rule: rule, effectiveFrom: from)
                    context.insert(schedule)
                    schedule.habit = habit
                }
            }
        } else {
            let start = LocalDate(startDate, dayEndsAtHour: 0)
            let habit = Habit(
                name: name.trimmingCharacters(in: .whitespaces), symbol: symbol, colorName: colorName,
                kind: kind, target: target, unit: unit, sortOrder: nextSortOrder,
                startDate: min(start, LocalDate(.now, dayEndsAtHour: dayEnds)))
            habit.reminderMinutes = reminderMinutes
            context.insert(habit)
            let schedule = HabitSchedule(rule: rule, effectiveFrom: habit.localStartDate)
            context.insert(schedule)
            schedule.habit = habit
        }
        HabitActions.save(context)
        dismiss()
    }
}

/// Seven toggle chips in the user's week order.
struct WeekdayChips: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let first = Calendar.current.firstWeekday
        let days = (0..<7).map { (first - 1 + $0) % 7 + 1 }
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    withAnimation(.snappy) {
                        if on { selection.remove(day) } else { selection.insert(day) }
                    }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? .white : .primary)
                        .background(on ? Color.accentColor : Color.primary.opacity(0.06), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

#Preview("New") {
    HabitEditorView(habit: nil, nextSortOrder: 0)
        .modelContainer(PreviewData.container)
}

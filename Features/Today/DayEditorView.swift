import Engine
import SwiftData
import SwiftUI

/// Edit one habit on one day: value, skip, note. Works for any past day.
struct DayEditorView: View {
    let habit: Habit
    let date: LocalDate
    var showsDoneButton = true

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        let engine = habit.engine()
        let log = habit.log(on: date)
        let value = log?.value ?? 0
        let skipped = log?.isSkipped ?? false

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status", value: statusText(engine.status(on: date)))
                    if habit.kind == .binary {
                        Toggle("Done", isOn: Binding(
                            get: { value >= 1 },
                            set: { HabitActions.setValue($0 ? 1 : 0, for: habit, on: date, in: context) }))
                    } else {
                        Stepper(value: Binding(
                            get: { value },
                            set: { HabitActions.setValue(max(0, $0), for: habit, on: date, in: context) }),
                                in: 0...10_000, step: habit.step) {
                            LabeledContent(habit.kind == .timed ? "Minutes" : (habit.unit.isEmpty ? "Amount" : habit.unit.capitalized)) {
                                Text(value.amountText)
                                    .numberStyle()
                                    .contentTransition(.numericText(value: value))
                            }
                        }
                    }
                    Toggle("Skip (rest day)", isOn: Binding(
                        get: { skipped },
                        set: { HabitActions.setSkipped($0, for: habit, on: date, in: context) }))
                } footer: {
                    Text("Skipped days neither break nor extend a streak.")
                }

                Section("Note") {
                    TextField("How did it go?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .onSubmit { saveNote() }
                }

                Section {
                    Button("Clear Day", role: .destructive) {
                        HabitActions.reset(habit, on: date, in: context)
                        note = ""
                    }
                    .disabled(log == nil)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            saveNote()
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { note = habit.log(on: date)?.note ?? "" }
            .onChange(of: date) { old, new in
                saveNote(for: old)
                note = habit.log(on: new)?.note ?? ""
            }
            .onDisappear { saveNote() }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveNote(for day: LocalDate? = nil) {
        let day = day ?? date
        let current = habit.log(on: day)?.note ?? ""
        guard note != current else { return }
        HabitActions.setNote(note, for: habit, on: day, in: context)
    }

    private func statusText(_ status: DayStatus) -> String {
        switch status {
        case .completed: String(localized: "Completed")
        case .partial: String(localized: "Partly done")
        case .skipped: String(localized: "Skipped")
        case .missed: String(localized: "Missed")
        case .notScheduled: String(localized: "Not scheduled")
        case .pending: String(localized: "Not done yet")
        }
    }
}

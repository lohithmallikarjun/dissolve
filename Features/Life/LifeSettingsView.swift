import Engine
import SwiftData
import SwiftUI

/// Birth date, lifespan and eras.
struct LifeSettingsView: View {
    let profile: LifeProfile?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var birth = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var lifespan = 80
    @State private var eras: [EditableEra] = []
    @State private var loaded = false

    struct EditableEra: Identifiable {
        let id = UUID()
        var name: String
        var start: Date
        var end: Date
        var ongoing: Bool
        var colorName: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Born", selection: $birth, in: ...Date.now, displayedComponents: .date)
                    Stepper("Lifespan: \(lifespan) years", value: $lifespan, in: 40...120)
                        .numberStyle()
                } footer: {
                    Text("Each row of the grid is one year, starting on your birthday.")
                }
                Section {
                    ForEach($eras) { $era in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Era", text: $era.name, prompt: Text("e.g. University"))
                                Menu {
                                    ForEach(HabitColor.allCases) { color in
                                        Button(color.rawValue.capitalized) { era.colorName = color.rawValue }
                                    }
                                } label: {
                                    Circle().fill(HabitColor.named(era.colorName).color).frame(width: 18, height: 18)
                                }
                            }
                            DatePicker("From", selection: $era.start, displayedComponents: .date)
                            Toggle("Ongoing", isOn: $era.ongoing)
                            if !era.ongoing {
                                DatePicker("To", selection: $era.end, displayedComponents: .date)
                            }
                        }
                    }
                    .onDelete { eras.remove(atOffsets: $0) }
                    Button("Add Era", systemImage: "plus") {
                        eras.append(EditableEra(name: "", start: birth, end: .now, ongoing: true,
                                                colorName: HabitColor.allCases[eras.count % 12].rawValue))
                    }
                } header: {
                    Text("Eras")
                } footer: {
                    Text("Coloured bands on the grid, like School, University or a city you lived in.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Your Life")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let profile, let date = profile.birth else { return }
        birth = date.startDate()
        lifespan = profile.lifespanYears
        eras = profile.eras.map {
            EditableEra(name: $0.name, start: $0.start.startDate(), end: ($0.end ?? AppSettings.today()).startDate(),
                        ongoing: $0.end == nil, colorName: $0.colorName)
        }
    }

    private func save() {
        let birthDay = LocalDate(birth, dayEndsAtHour: 0)
        let target = profile ?? {
            let new = LifeProfile(birthDate: birthDay, lifespanYears: lifespan)
            context.insert(new)
            return new
        }()
        target.birthDate = birthDay.description
        target.lifespanYears = lifespan
        target.eras = eras
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { LifeEra(name: $0.name, start: LocalDate($0.start, dayEndsAtHour: 0),
                           end: $0.ongoing ? nil : LocalDate($0.end, dayEndsAtHour: 0), colorName: $0.colorName) }
        Persistence.save(context)
        dismiss()
    }
}

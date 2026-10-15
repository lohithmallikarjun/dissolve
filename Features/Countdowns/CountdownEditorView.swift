import Engine
import PhotosUI
import SwiftData
import SwiftUI

struct CountdownEditorView: View {
    let countdown: Countdown?
    let nextSortOrder: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var symbol = "calendar"
    @State private var colorName = HabitColor.orange.rawValue
    @State private var date = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var isAllDay = true
    @State private var repeatsYearly = false
    @State private var countUp = false
    @State private var photoID: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var loaded = false

    static let symbols = ["calendar", "airplane", "birthday.cake.fill", "gift.fill", "figure.run", "heart.fill",
                          "graduationcap.fill", "party.popper.fill", "beach.umbrella.fill", "house.fill",
                          "briefcase.fill", "star.fill", "music.note", "leaf.fill", "sparkles", "flag.checkered"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("e.g. Marathon"))
                        .font(.title3)
                }
                Section {
                    Picker("Counts", selection: $countUp) {
                        Text("Down to a date").tag(false)
                        Text("Up from a date").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Toggle("All day", isOn: $isAllDay)
                    DatePicker(countUp ? "Since" : "Date", selection: $date,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    if !countUp {
                        Toggle("Repeats every year", isOn: $repeatsYearly)
                    }
                } footer: {
                    Text(countUp ? "Shows how many days have passed." :
                         repeatsYearly ? "Birthdays and anniversaries roll over to next year." :
                         "On the day you'll get a little celebration; the next day it's archived.")
                }
                Section("Look") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(Self.symbols, id: \.self) { name in
                            Button { withAnimation(.snappy) { symbol = name } } label: {
                                Image(systemName: name)
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(symbol == name ? .white : HabitColor.named(colorName).color)
                                    .background(symbol == name ? HabitColor.named(colorName).color : Color.primary.opacity(0.06),
                                                in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(HabitColor.allCases) { color in
                            Button { withAnimation(.snappy) { colorName = color.rawValue } } label: {
                                Circle().fill(color.color).frame(width: 28, height: 28)
                                    .overlay {
                                        if colorName == color.rawValue {
                                            Circle().strokeBorder(.white, lineWidth: 3).padding(3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(color.name))
                        }
                    }
                    HStack {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photoID == nil ? "Add Background Photo" : "Change Photo", systemImage: "photo")
                        }
                        if photoID != nil {
                            Spacer()
                            Button("Remove", role: .destructive) { photoID = nil }
                        }
                    }
                }
                if let countdown {
                    Section {
                        Button("Archive", systemImage: "archivebox") {
                            countdown.archivedAt = .now
                            Persistence.save(context)
                            dismiss()
                        }
                        Button("Delete Countdown", systemImage: "trash", role: .destructive) {
                            context.delete(countdown)
                            Persistence.save(context)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(countdown == nil ? "New Countdown" : "Edit Countdown")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let saved = try? await Task.detached(operation: { try ImageStore.save(imageData: data) }).value
                    else { return }
                    let photo = Photo(id: saved.id, width: saved.width, height: saved.height)
                    context.insert(photo)
                    photoID = saved.id.uuidString
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }

    private func load() {
        guard !loaded, let countdown else { return }
        loaded = true
        title = countdown.title
        symbol = countdown.symbol
        colorName = countdown.colorName
        date = countdown.targetDate
        isAllDay = countdown.isAllDay
        repeatsYearly = countdown.repeatsYearly
        countUp = countdown.countUp
        photoID = countdown.photoID
    }

    private func save() {
        let target = countdown ?? {
            let new = Countdown(title: title, symbol: symbol, colorName: colorName, targetDate: date, isAllDay: isAllDay)
            new.sortOrder = nextSortOrder
            context.insert(new)
            return new
        }()
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.symbol = symbol
        target.colorName = colorName
        target.targetDate = date
        target.isAllDay = isAllDay
        target.repeatsYearly = repeatsYearly && !countUp
        target.countUp = countUp
        target.photoID = photoID
        target.archivedAt = nil
        Persistence.save(context)
        dismiss()
    }
}

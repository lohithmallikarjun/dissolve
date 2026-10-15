import Engine
import SwiftData
import SwiftUI

/// Newest-first entries; "+" opens today's. Locked behind Face ID / Touch ID, blurred in the app switcher.
struct JournalView: View {
    @Environment(AppModel.self) private var model
    @Environment(JournalLock.self) private var lock
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]

    @State private var opened: JournalEntry?
    @State private var showingTemplates = false
    @Query(sort: \JournalTemplate.createdAt) private var templates: [JournalTemplate]
    #if os(macOS)
    @State private var selectedID: UUID?
    @State private var showsInspector = true
    #endif

    var body: some View {
        Group {
            if lock.isLocked {
                JournalLockedView()
            } else {
                content
            }
        }
        .overlay {
            if scenePhase != .active {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
        }
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Entry", systemImage: "square.and.pencil") { open(model.today) }
                    .disabled(lock.isLocked)
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    if templates.count > 1, JournalStore.entry(on: model.today, in: context) == nil {
                        Section("Today's entry from") {
                            ForEach(templates) { template in
                                Button(template.name) { open(model.today, template: template) }
                            }
                        }
                    }
                    Button("Templates…", systemImage: "doc.text") { showingTemplates = true }
                }
                .disabled(lock.isLocked)
            }
        }
        .sheet(isPresented: $showingTemplates) {
            NavigationStack {
                TemplatesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showingTemplates = false } }
                    }
            }
        }
        .onChange(of: model.journalDate, initial: true) { _, date in
            guard let date, !lock.isLocked else { return }
            open(date)
            model.journalDate = nil
        }
        .onChange(of: lock.isUnlocked) { _, unlocked in
            if unlocked, let date = model.journalDate {
                open(date)
                model.journalDate = nil
            }
        }
    }

    private func open(_ date: LocalDate, template: JournalTemplate? = nil) {
        let entry = JournalStore.entryCreatingIfNeeded(on: date, template: template, in: context)
        #if os(macOS)
        selectedID = entry.id
        #else
        opened = entry
        #endif
    }

    /// An entry from this date in an earlier year.
    private var onThisDay: JournalEntry? {
        let dates = entries.compactMap(\.localDate)
        guard let date = JournalStats.onThisDay(dates, today: model.today).first else { return nil }
        return entries.first { $0.localDate == date }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                if let memory = onThisDay {
                    Section("On this day") {
                        EntryRow(entry: memory).tag(memory.id)
                    }
                }
                ForEach(entries) { entry in
                    EntryRow(entry: entry).tag(entry.id)
                }
            }
            .frame(width: 280)
            Divider()
            if let entry = entries.first(where: { $0.id == selectedID }) {
                JournalEntryEditor(entry: entry)
                    .id(entry.id)
                    .inspector(isPresented: $showsInspector) {
                        EntryInspector(entry: entry)
                            .inspectorColumnWidth(min: 200, ideal: 240)
                    }
            } else {
                ContentUnavailableView("Select an entry", systemImage: "book",
                                       description: Text("Or press ⌘N for today's."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #else
        ScrollView {
            LazyVStack(spacing: 12) {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No entries yet", systemImage: "book")
                    } description: {
                        Text("Write a few lines about today.")
                    } actions: {
                        Button("Write Today's Entry") { open(model.today) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                }
                if let memory = onThisDay {
                    Button { opened = memory } label: { OnThisDayCard(entry: memory, today: model.today) }
                        .buttonStyle(.plain)
                }
                ForEach(entries) { entry in
                    Button { opened = entry } label: { EntryCard(entry: entry) }
                        .buttonStyle(.plain)
                        .scrollTransition(.animated(.smooth)) { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.96)
                        }
                }
            }
            .padding(Metrics.margin)
        }
        .navigationDestination(item: $opened) { JournalEntryEditor(entry: $0) }
        #endif
    }
}

struct JournalLockedView: View {
    @Environment(JournalLock.self) private var lock

    var body: some View {
        ContentUnavailableView {
            Label("Journal Locked", systemImage: "lock.fill")
        } description: {
            Text(lock.failure ?? String(localized: "Unlock with \(lock.biometryName) to read and write."))
        } actions: {
            Button("Unlock") { Task { await lock.unlock() } }
                .buttonStyle(.borderedProminent)
        }
        .task { await lock.unlock() }
    }
}

/// "On this day" — the same date in an earlier year.
struct OnThisDayCard: View {
    let entry: JournalEntry
    let today: LocalDate

    var body: some View {
        HStack(spacing: 14) {
            if let id = entry.photoIDs.first.flatMap(UUID.init(uuidString:)) {
                PhotoThumbnail(id: id)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 14))
                    .privacySensitive()
            }
            VStack(alignment: .leading, spacing: 4) {
                let years = (entry.localDate?.year).map { today.year - $0 } ?? 1
                Label(years == 1 ? "On this day · a year ago" : "On this day · \(years) years ago",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Text(entry.firstLine.isEmpty ? String(localized: "An entry without text") : entry.firstLine)
                    .font(.subheadline)
                    .lineLimit(3)
                    .privacySensitive()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.indigo.opacity(0.35), lineWidth: 1)
        }
    }
}

/// iPhone list card: thumbnail, date, mood, first line.
struct EntryCard: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.localDate?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? entry.date)
                        .font(.headline)
                    Spacer()
                    if let mood = Mood(rawValue: entry.mood) {
                        Image(systemName: mood.symbol)
                            .foregroundStyle(mood.color)
                            .accessibilityLabel(Text(mood.name))
                    }
                }
                Text(entry.firstLine.isEmpty ? String(localized: "No text yet") : entry.firstLine)
                    .font(.subheadline)
                    .foregroundStyle(entry.firstLine.isEmpty ? .tertiary : .secondary)
                    .lineLimit(2)
                    .privacySensitive()
                Text("\(entry.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .numberStyle()
            }
            if let id = entry.photoIDs.first.flatMap(UUID.init(uuidString:)) {
                PhotoThumbnail(id: id)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 12))
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}

/// Mac list row.
struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.localDate?.formatted(.dateTime.month(.abbreviated).day().year()) ?? entry.date)
                    .font(.headline)
                Spacer()
                if let mood = Mood(rawValue: entry.mood) {
                    Image(systemName: mood.symbol).foregroundStyle(mood.color)
                }
            }
            Text(entry.firstLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct EntryInspector: View {
    let entry: JournalEntry

    var body: some View {
        Form {
            LabeledContent("Date", value: entry.localDate?.formatted() ?? entry.date)
            LabeledContent("Words", value: entry.wordCount, format: .number)
            LabeledContent("Photos", value: entry.photoIDs.count, format: .number)
            LabeledContent("Mood", value: Mood(rawValue: entry.mood).map { String(localized: $0.name) } ?? "—")
            LabeledContent("Updated", value: entry.updatedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .formStyle(.grouped)
    }
}

extension Mood {
    var color: Color {
        switch self {
        case .awful: .indigo
        case .bad: .blue
        case .okay: .teal
        case .good: .orange
        case .great: .yellow
        }
    }
}

#Preview {
    NavigationStack { JournalView() }
        .environment(AppModel())
        .environment(JournalLock())
        .modelContainer(PreviewData.container)
}

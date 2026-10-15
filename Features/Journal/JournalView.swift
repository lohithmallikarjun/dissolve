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

    private func open(_ date: LocalDate) {
        let entry = JournalStore.entryCreatingIfNeeded(on: date, in: context)
        #if os(macOS)
        selectedID = entry.id
        #else
        opened = entry
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            List(selection: $selectedID) {
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

import Engine
import PhotosUI
import SwiftData
import SwiftUI

/// All journal templates: which is the default, and which weekdays use which.
struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JournalTemplate.createdAt) private var templates: [JournalTemplate]
    @State private var editing: JournalTemplate?

    var body: some View {
        List {
            Section {
                ForEach(templates) { template in
                    Button { editing = template } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).foregroundStyle(.primary)
                                Text(subtitle(template)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if template.isDefault {
                                Text("Default").font(.caption.weight(.semibold)).foregroundStyle(.green)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets where !templates[index].isDefault { context.delete(templates[index]) }
                    Persistence.save(context)
                }
            } footer: {
                Text("A new entry copies its template, so editing a template never changes past entries. Assign weekdays to use a template on those days.")
            }
            Button("New Template", systemImage: "plus") {
                let template = JournalTemplate(name: String(localized: "New Template"), isDefault: false)
                context.insert(template)
                for (index, kind) in [BlockKind.heading, .prompt, .text].enumerated() {
                    let block = TemplateBlock(kind: kind, order: index,
                                              promptText: kind == .heading ? template.name : kind == .prompt ? String(localized: "What's on your mind?") : "",
                                              placeholder: kind == .text ? String(localized: "Write…") : "")
                    context.insert(block)
                    block.template = template
                }
                Persistence.save(context)
                editing = template
            }
        }
        .navigationTitle("Templates")
        .task { _ = JournalStore.allTemplates(in: context) }
        .sheet(item: $editing) { TemplateEditorView(template: $0) }
    }

    private func subtitle(_ template: JournalTemplate) -> String {
        let blocks = String(localized: "\(template.blocks.count) blocks")
        guard !template.weekdays.isEmpty else { return blocks }
        let symbols = Calendar.current.shortWeekdaySymbols
        return blocks + " · " + template.weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}

struct TemplateEditorView: View {
    @Bindable var template: JournalTemplate
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalTemplate.createdAt) private var allTemplates: [JournalTemplate]
    @State private var weekdays: Set<Int> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $template.name)
                    Toggle("Default template", isOn: Binding(
                        get: { template.isDefault },
                        set: { on in
                            guard on else { return }
                            for t in allTemplates { t.isDefault = t === template }
                        }))
                }
                Section {
                    WeekdayChips(selection: $weekdays)
                } header: {
                    Text("Use on")
                } footer: {
                    Text("Days not assigned to any template use the default.")
                }
                Section("Blocks") {
                    ForEach(template.orderedBlocks) { block in
                        TemplateBlockRow(block: block)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                    Menu {
                        ForEach(BlockKind.allCases, id: \.self) { kind in
                            Button(Self.name(kind), systemImage: Self.symbol(kind)) { add(kind) }
                        }
                    } label: {
                        Label("Add Block", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        template.weekdays = weekdays.sorted()
                        // A weekday belongs to one template.
                        for other in allTemplates where other !== template {
                            other.weekdays.removeAll { weekdays.contains($0) }
                        }
                        Persistence.save(context)
                        dismiss()
                    }
                }
            }
            .onAppear { weekdays = Set(template.weekdays) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func move(from source: IndexSet, to destination: Int) {
        var blocks = template.orderedBlocks
        blocks.move(fromOffsets: source, toOffset: destination)
        for (index, block) in blocks.enumerated() { block.order = index }
    }

    private func delete(at offsets: IndexSet) {
        let blocks = template.orderedBlocks
        for index in offsets { context.delete(blocks[index]) }
    }

    private func add(_ kind: BlockKind) {
        let block = TemplateBlock(kind: kind, order: (template.blocks.map(\.order).max() ?? -1) + 1,
                                  promptText: Self.defaultPrompt(kind))
        context.insert(block)
        block.template = template
    }

    static func name(_ kind: BlockKind) -> LocalizedStringKey {
        switch kind {
        case .heading: "Heading"
        case .prompt: "Prompt"
        case .text: "Text"
        case .checklist: "Checklist"
        case .image: "Image"
        case .mood: "Mood"
        case .rating: "Rating"
        case .habitSummary: "Habit Summary"
        }
    }

    static func symbol(_ kind: BlockKind) -> String {
        switch kind {
        case .heading: "textformat.size"
        case .prompt: "questionmark.bubble"
        case .text: "text.alignleft"
        case .checklist: "checklist"
        case .image: "photo"
        case .mood: "sun.max"
        case .rating: "star"
        case .habitSummary: "checkmark.circle"
        }
    }

    static func defaultPrompt(_ kind: BlockKind) -> String {
        switch kind {
        case .heading: String(localized: "Heading")
        case .prompt: String(localized: "What are you grateful for?")
        case .text, .image: ""
        case .checklist: String(localized: "Today")
        case .mood: String(localized: "How was today?")
        case .rating: String(localized: "Rate the day")
        case .habitSummary: String(localized: "Habits")
        }
    }
}

private struct TemplateBlockRow: View {
    @Bindable var block: TemplateBlock
    @Environment(\.modelContext) private var context
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(TemplateEditorView.name(block.kind), systemImage: TemplateEditorView.symbol(block.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch block.kind {
            case .text:
                TextField("Placeholder", text: $block.placeholder)
            case .checklist:
                TextField("Title", text: $block.promptText)
                TextField("Items, one per line", text: Binding(
                    get: { block.checklistItems.joined(separator: "\n") },
                    set: { block.checklistItems = $0.split(separator: "\n").map(String.init) }), axis: .vertical)
                    .lineLimit(2...6)
            case .image:
                TextField("Title", text: $block.promptText)
                HStack {
                    if let id = block.imageID.flatMap(UUID.init(uuidString:)) {
                        PhotoThumbnail(id: id).frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(block.imageID == nil ? "Add a template image" : "Change image")
                    }
                    if block.imageID != nil {
                        Button("Remove", role: .destructive) { block.imageID = nil }
                    }
                }
            case .prompt:
                TextField("Question", text: $block.promptText)
                TextField("Placeholder", text: $block.placeholder)
            default:
                TextField("Title", text: $block.promptText)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let saved = try? await Task.detached(operation: { try ImageStore.save(imageData: data) }).value
                else { return }
                context.insert(Photo(id: saved.id, width: saved.width, height: saved.height))
                block.imageID = saved.id.uuidString
            }
        }
    }
}

import Engine
import PhotosUI
import SwiftData
import SwiftUI

/// Edits one day's entry: its blocks in order. Saves a moment after typing stops.
struct JournalEntryEditor: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var context
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(entry.localDate?.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? entry.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(entry.orderedBlocks) { block in
                    BlockEditor(block: block, entry: entry, onEdit: scheduleSave)
                }
                Text("\(entry.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .numberStyle()
                    .contentTransition(.numericText(value: Double(entry.wordCount)))
            }
            .padding(Metrics.margin)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(entry.localDate?.relativeName(today: AppSettings.today()) ?? "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear(perform: saveNow)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        withAnimation(.snappy) { entry.recountWords() }
        if context.hasChanges { Persistence.save(context) }
    }
}

private struct BlockEditor: View {
    @Bindable var block: EntryBlock
    @Bindable var entry: JournalEntry
    let onEdit: () -> Void

    var body: some View {
        switch block.kind {
        case .heading:
            Text(block.promptText).font(.title2.weight(.bold))
        case .prompt:
            VStack(alignment: .leading, spacing: 8) {
                Text(block.promptText).font(.headline)
                textField
            }
        case .text:
            textField
        case .image:
            PhotoBlockView(block: block)
        case .mood:
            VStack(alignment: .leading, spacing: 8) {
                Text(block.promptText.isEmpty ? String(localized: "Mood") : block.promptText).font(.headline)
                MoodPicker(mood: $entry.mood)
                    .onChange(of: entry.mood) { onEdit() }
            }
        case .rating:
            VStack(alignment: .leading, spacing: 8) {
                Text(block.promptText).font(.headline)
                HStack {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            withAnimation(.snappy) { block.rating = star }
                            onEdit()
                        } label: {
                            Image(systemName: star <= block.rating ? "star.fill" : "star")
                                .foregroundStyle(.yellow)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .checklist, .habitSummary:
            Text(block.promptText).font(.headline).foregroundStyle(.secondary)
        }
    }

    private var textField: some View {
        TextField(block.placeholder, text: $block.text, axis: .vertical)
            .lineLimit(3...)
            .textFieldStyle(.plain)
            .privacySensitive()
            .onChange(of: block.text) { onEdit() }
    }
}

struct MoodPicker: View {
    @Binding var mood: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Mood.allCases) { option in
                let selected = mood == option.rawValue
                Button {
                    withAnimation(.snappy) { mood = selected ? 0 : option.rawValue }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: option.symbol)
                            .font(.title2)
                            .symbolEffect(.bounce, value: selected)
                        Text(option.name).font(.caption2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .foregroundStyle(selected ? option.color : .secondary)
                    .background(selected ? option.color.opacity(0.15) : Color.primary.opacity(0.05),
                                in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.name))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: mood)
    }
}

/// Photos in an image block: pick several, drop or paste on Mac. Stored resized, as files.
struct PhotoBlockView: View {
    @Bindable var block: EntryBlock
    @Environment(\.modelContext) private var context
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importing = 0
    @State private var viewing: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(block.promptText.isEmpty ? String(localized: "Photos") : block.promptText).font(.headline)
                Spacer()
                if importing > 0 { ProgressView().controlSize(.small) }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                }
            }
            if !block.photoIDs.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(block.photoIDs, id: \.self) { idString in
                        if let id = UUID(uuidString: idString) {
                            PhotoThumbnail(id: id)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .clipShape(.rect(cornerRadius: 12))
                                .contentShape(.rect)
                                .onTapGesture { viewing = id }
                                .contextMenu {
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        withAnimation(.smooth) {
                                            JournalStore.removePhoto(idString, from: block, in: context)
                                        }
                                    }
                                }
                                .privacySensitive()
                        }
                    }
                }
            } else {
                #if os(macOS)
                Text("Drop or paste images here.").font(.caption).foregroundStyle(.secondary)
                #endif
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { await add(data) }
                }
            }
        }
        #if os(macOS)
        .dropDestination(for: DroppedImage.self) { images, _ in
            Task { for image in images { await add(image.data) } }
            return !images.isEmpty
        }
        .pasteDestination(for: DroppedImage.self) { images in
            Task { for image in images { await add(image.data) } }
        }
        #endif
        .sheet(item: $viewing) { id in
            PhotoViewer(id: id)
        }
    }

    private func add(_ data: Data) async {
        importing += 1
        defer { importing -= 1 }
        guard let saved = try? await Task.detached(operation: { try ImageStore.save(imageData: data) }).value else { return }
        withAnimation(.smooth) { JournalStore.addPhoto(saved, to: block, in: context) }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct DroppedImage: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedImage(data: $0) }
    }
}

/// Loads a thumbnail from disk.
struct PhotoThumbnail: View {
    let id: UUID
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.06))
            if let image {
                Image(platformImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .task(id: id) { image = ImageStore.thumbnail(id: id) }
    }
}

struct PhotoViewer: View {
    let id: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = ImageStore.image(id: id) ?? ImageStore.thumbnail(id: id) {
                    Image(platformImage: image).resizable().scaledToFit()
                } else {
                    ContentUnavailableView("Photo not downloaded yet", systemImage: "icloud.and.arrow.down")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}

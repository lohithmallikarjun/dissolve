import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// The Milestone 0 go/no-go checks: App Group + widget, then the iCloud Drive folder.
struct DiagnosticsView: View {
    let storeStatus: StoreStatus

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncFolderStore.self) private var syncFolder
    @Query(sort: \DiagnosticPing.updatedAt, order: .reverse) private var pings: [DiagnosticPing]

    @State private var counter = AppGroup.defaults.integer(forKey: SharedKeys.diagnosticCounter)
    @State private var isPickingFolder = false
    @State private var saveError: String?

    var body: some View {
        Form {
            appGroupSection
            folderSection
            deviceSection
        }
        .formStyle(.grouped)
        .navigationTitle("Milestone 0")
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            syncFolder.select(result)
        }
        .task {
            await syncFolder.readTestFiles()
        }
    }

    // MARK: 1 · App Group + widget

    private var appGroupSection: some View {
        Section {
            CheckRow(title: "App Group container", ok: AppGroup.containerURL != nil)
            CheckRow(title: "SwiftData in App Group", ok: storeStatus.usesAppGroup, detail: storeStatus.failure)
            LabeledContent("Test value") {
                Text(counter, format: .number)
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(counter)))
            }
            LabeledContent("SwiftData pings", value: pings.count, format: .number)
            Button("Write test value", systemImage: "plus.circle.fill", action: writeTestValue)
                .sensoryFeedback(.increase, trigger: counter)
            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
        } header: {
            Text("1 · App Group and widget")
        } footer: {
            Text("Add the “Dissolve Test” widget. After you tap Write, it should show the same number.")
        }
    }

    private func writeTestValue() {
        withAnimation(.snappy) { counter += 1 }
        let defaults = AppGroup.defaults
        defaults.set(counter, forKey: SharedKeys.diagnosticCounter)
        defaults.set(Date.now, forKey: SharedKeys.diagnosticUpdatedAt)
        modelContext.insert(DiagnosticPing(value: counter, deviceName: DeviceIdentity.name))
        do {
            try modelContext.save()
            saveError = nil
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: 2 · iCloud Drive folder

    private var folderSection: some View {
        Section {
            CheckRow(
                title: "Sync folder",
                ok: syncFolder.folderURL != nil,
                detail: syncFolder.folderName ?? "Not chosen")
            Button(
                syncFolder.folderURL == nil ? "Choose iCloud Drive folder…" : "Change folder…",
                systemImage: "folder.badge.plus"
            ) { isPickingFolder = true }

            if syncFolder.folderURL != nil {
                Button("Write test file", systemImage: "square.and.arrow.down") {
                    Task { await syncFolder.writeTestFile(appGroupValue: counter) }
                }
                Button("Read test files", systemImage: "arrow.clockwise") {
                    Task { await syncFolder.readTestFiles() }
                }
            }

            if syncFolder.isWorking {
                ProgressView()
            }
            if let message = syncFolder.message {
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(message.isError ? .red : .secondary)
            }
            ForEach(syncFolder.files) { file in
                DiagnosticFileRow(file: file, isThisDevice: file.payload?.deviceID == DeviceIdentity.id)
            }
        } header: {
            Text("2 · iCloud Drive folder")
        } footer: {
            Text("On both iPhone and Mac, choose the same folder, e.g. iCloud Drive › Dissolve. Write on one device, then Read on the other.")
        }
    }

    // MARK: 3 · Device

    private var deviceSection: some View {
        Section("3 · This device") {
            LabeledContent("Name", value: DeviceIdentity.name)
            LabeledContent("Platform", value: DeviceIdentity.platform)
            LabeledContent("Device ID") {
                Text(DeviceIdentity.id).font(.caption.monospaced()).textSelection(.enabled)
            }
        }
    }
}

private struct CheckRow: View {
    let title: String
    let ok: Bool
    var detail: String?

    var body: some View {
        LabeledContent {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(ok ? .green : .red)
                .symbolEffect(.bounce, value: ok)
        } label: {
            Text(title)
            if let detail {
                Text(detail)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(ok ? "Working" : "Not working")
    }
}

private struct DiagnosticFileRow: View {
    let file: DiagnosticFile
    let isThisDevice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let payload = file.payload {
                HStack {
                    Image(systemName: payload.platform == "macOS" ? "laptopcomputer" : "iphone")
                    Text(payload.deviceName).font(.headline)
                    if isThisDevice {
                        Text("this device").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Value \(payload.appGroupValue) · \(payload.writtenAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text(file.fileName).font(.headline)
                Text(file.problem ?? "Unreadable").font(.subheadline).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView(storeStatus: .preview)
    }
    .environment(SyncFolderStore(defaults: UserDefaults(suiteName: "preview")!))
    .modelContainer(SharedModelContainer.inMemory())
}

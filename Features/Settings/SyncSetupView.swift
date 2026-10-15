import SwiftUI
import UniformTypeIdentifiers

/// First launch: pick the iCloud Drive folder both devices share.
struct SyncSetupView: View {
    let onDone: () -> Void
    @Environment(SyncFolderStore.self) private var syncFolder
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.and.arrow.up.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: syncFolder.folderURL)
            Text("Sync your iPhone and Mac").font(.title2.weight(.bold))
            Text("Choose a folder in iCloud Drive — e.g. iCloud Drive › Dissolve. Pick the same folder on your other device. Each device writes only its own files, so nothing gets overwritten.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let name = syncFolder.folderName {
                Label(name, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Button(syncFolder.folderURL == nil ? "Choose Folder…" : "Done") {
                if syncFolder.folderURL == nil { picking = true } else { finish() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not Now") { finish() }
        }
        .padding(32)
        .frame(maxWidth: 460)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { syncFolder.select($0) }
        .interactiveDismissDisabled()
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

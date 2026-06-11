import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add Magnet View

struct AddMagnetView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var magnetURL = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                    .font(.title2)
                Text("Add Magnet Link")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Magnet link or .torrent URL")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("magnet:?xt=urn:btih:…", text: $magnetURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .onAppear {
                            // Auto-add only unambiguous magnet links. Plain
                            // http(s) URLs are prefilled but require explicit
                            // confirmation — any random URL could be sitting
                            // in the pasteboard.
                            guard let clip = NSPasteboard.general.string(forType: .string) else { return }
                            let trimmed = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.hasPrefix("magnet:") {
                                magnetURL = trimmed
                                addMagnet()
                            } else if isMagnetOrTorrentURL(trimmed) {
                                magnetURL = trimmed
                            }
                        }
                        .onChange(of: magnetURL) { _, new in
                            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.hasPrefix("magnet:") && !isLoading {
                                addMagnet()
                            }
                        }
                }

                if let error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error)
                    }
                    .foregroundStyle(.red)
                    .font(.callout)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button {
                    addMagnet()
                } label: {
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(magnetURL.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding()
        }
        .frame(width: 480)
    }

    private func isMagnetOrTorrentURL(_ s: String) -> Bool {
        s.hasPrefix("magnet:") || s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    private func addMagnet() {
        let url = magnetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !isLoading else { return }
        isLoading = true
        error = nil

        Task {
            do {
                _ = try await store.addMagnet(url)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Add Torrent Sheet (file picker result)

struct AddTorrentSheetView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Open a .torrent file from Finder\nor drop it directly into the window.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Choose a file…") {
                openFilePicker()
            }
            .buttonStyle(.borderedProminent)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .padding(40)
        .frame(width: 380)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent")!]
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            isLoading = true
            Task {
                do {
                    for url in panel.urls {
                        _ = try await store.addFile(at: url)
                    }
                    await MainActor.run { dismiss() }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        }
    }
}

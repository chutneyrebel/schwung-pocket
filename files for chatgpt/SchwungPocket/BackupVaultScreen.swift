import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation

private enum VaultFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case audio = "Audio"
    case sets = "Sets"
    case other = "Other"

    var id: String { rawValue }

    func includes(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let audio = VaultFileKinds.audioExtensions.contains(ext)
        let set = VaultFileKinds.setExtensions.contains(ext)
        switch self {
        case .all: return true
        case .audio: return audio
        case .sets: return set
        case .other: return !audio && !set
        }
    }
}

private enum VaultSort: String, CaseIterable, Identifiable {
    case recent = "Last modified"
    case name = "Name"
    case largest = "Largest first"

    var id: String { rawValue }
}

private enum VaultFileKinds {
    static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "mp3", "m4a", "aac", "caf", "mp4", "flac", "ogg", "opus"]
    static let previewableAudioExtensions: Set<String> = ["wav", "aif", "aiff", "mp3", "m4a", "aac", "caf", "mp4"]
    static let setExtensions: Set<String> = ["ablbundle", "als", "adv", "adg", "alp"]

    static func isPreviewableAudio(_ url: URL) -> Bool {
        previewableAudioExtensions.contains(url.pathExtension.lowercased())
    }

    static func symbol(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) { return "waveform" }
        if setExtensions.contains(ext) { return "music.note.list" }
        if ["zip", "tar", "gz", "7z"].contains(ext) { return "doc.zipper" }
        return "doc.text"
    }
}

private struct VaultFileMetadata: Codable, Equatable {
    var tags = ""
    var bpm = ""
    var musicalKey = ""
    var notes = ""

    var tagList: [String] {
        tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        bpm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        musicalKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct FileEditTarget: Identifiable {
    let fileURL: URL
    var id: String { fileURL.path }
}

struct BackupVaultScreen: View {
    @State private var downloadedFiles: [URL] = []
    @State private var backupFiles: [URL] = []
    @State private var metadataByName: [String: VaultFileMetadata] = [:]
    @State private var isImporting = false
    @State private var searchText = ""
    @State private var filter: VaultFilter = .all
    @State private var sort: VaultSort = .recent
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var deleteTarget: URL?
    @State private var shareTarget: ShareTarget?
    @State private var editingTarget: FileEditTarget?
    @StateObject private var audioPreview = AudioPreviewPlayer()

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private var downloadsURL: URL { documentsURL.appendingPathComponent("Downloads", isDirectory: true) }
    private var backupsURL: URL { documentsURL.appendingPathComponent("Backups", isDirectory: true) }

    private var metadataURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? documentsURL.appendingPathComponent("Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("VaultMetadata.json")
    }

    private var visibleFiles: [URL] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = downloadedFiles.filter { file in
            guard filter.includes(file) else { return false }
            guard !query.isEmpty else { return true }
            let metadata = metadataByName[file.lastPathComponent] ?? VaultFileMetadata()
            let searchable = [file.lastPathComponent, metadata.tags, metadata.bpm, metadata.musicalKey, metadata.notes]
                .joined(separator: " ")
                .lowercased()
            return searchable.contains(query)
        }

        switch sort {
        case .recent:
            return matching.sorted { modifiedDate($0) > modifiedDate($1) }
        case .name:
            return matching.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        case .largest:
            return matching.sorted { fileSizeBytes($0) > fileSizeBytes($1) }
        }
    }

    private var audioCount: Int { downloadedFiles.filter { VaultFilter.audio.includes($0) }.count }
    private var setCount: Int { downloadedFiles.filter { VaultFilter.sets.includes($0) }.count }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    introCard
                    librarySummary
                    searchAndFilters
                    downloadsSection
                    backupsSection
                    limitationCard
                }
                .padding(18)
                .padding(.bottom, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Sample & Set Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { isImporting = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import files from Files")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Vault")
                }
            }
            .onAppear(perform: refresh)
            .onReceive(NotificationCenter.default.publisher(for: .schwungPocketDownloadFinished)) { _ in
                refresh()
            }
            .onDisappear { audioPreview.stop() }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.audio, .data, .item],
                allowsMultipleSelection: true,
                onCompletion: importFiles
            )
            .alert("Schwung Pocket", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(item: $shareTarget) { target in
                ActivitySheet(activityItems: [target.url])
            }
            .sheet(item: $editingTarget) { target in
                FileMetadataEditor(
                    fileName: target.fileURL.lastPathComponent,
                    initialValue: metadataByName[target.fileURL.lastPathComponent] ?? VaultFileMetadata()
                ) { value in
                    metadataByName[target.fileURL.lastPathComponent] = value
                    persistMetadata()
                }
            }
            .confirmationDialog(
                "Delete this saved backup?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete backup", role: .destructive) {
                    if let target = deleteTarget {
                        deleteBackup(target)
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This removes the local snapshot from this iPhone. It does not delete the original file in Downloads or on Move.")
            }
            .preferredColorScheme(.dark)
        }
    }

    private var introCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("YOUR SAMPLE + SET LIBRARY")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.6)
                            .foregroundStyle(Theme.muted)
                        Text("Find the sound. Keep the idea.")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                Text("Import audio, Sets and project files, preview compatible audio, and add tempo, key, tags and notes. Keep snapshots of important files before experimenting.")
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.muted)
                Button { isImporting = true } label: {
                    Label("Import samples or Sets", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
        }
    }

    private var librarySummary: some View {
        HStack(spacing: 10) {
            summaryTile(title: "LOCAL FILES", value: "\(downloadedFiles.count)", symbol: "folder", tint: Theme.blue)
            summaryTile(title: "AUDIO", value: "\(audioCount)", symbol: "waveform", tint: Theme.accent)
            summaryTile(title: "SETS", value: "\(setCount)", symbol: "music.note.list", tint: Theme.violet)
        }
    }

    private func summaryTile(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.muted)
                TextField("Search names, tags, keys…", text: $searchText)
                    .font(.system(size: 13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VaultFilter.allCases) { option in
                        Button { filter = option } label: {
                            Text(option.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(filter == option ? Theme.background : Theme.muted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(filter == option ? Theme.accent : Theme.surface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Menu {
                        Picker("Sort files", selection: $sort) {
                            ForEach(VaultSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.surfaceRaised, in: Capsule())
                    }
                }
            }
        }
    }

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("LIBRARY", detail: "\(visibleFiles.count) shown")
            if downloadedFiles.isEmpty {
                emptyState(
                    symbol: "waveform",
                    title: "Your library starts here",
                    detail: "Import audio, Sets or project files, or download files from Schwung Manager."
                )
            } else if visibleFiles.isEmpty {
                emptyState(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "No matching files",
                    detail: "Try another filter or search term. Tags, key, tempo and notes are searchable too."
                )
            } else {
                VStack(spacing: 9) {
                    ForEach(visibleFiles, id: \.path) { file in
                        libraryFileRow(file)
                    }
                }
            }
        }
    }

    private var backupsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("SNAPSHOTS", detail: "\(backupFiles.count) saved")
            if backupFiles.isEmpty {
                emptyState(
                    symbol: "archivebox",
                    title: "No snapshots yet",
                    detail: "Use a file's menu to save a dated copy before making changes."
                )
            } else {
                VStack(spacing: 9) {
                    ForEach(backupFiles, id: \.path) { file in
                        backupFileRow(file)
                    }
                }
            }
        }
    }

    private var limitationCard: some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("What this library can access", systemImage: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("This library manages files already imported or downloaded to the iPhone. It does not crawl the Move filesystem or edit an Ableton Set in place. Export a file through Schwung Manager first, then import or download it here. Restoring a snapshot creates a local copy; it does not upload to Move.")
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.7)
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted.opacity(0.85))
        }
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Theme.muted)
                .frame(width: 42, height: 42)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func libraryFileRow(_ url: URL) -> some View {
        let metadata = metadataByName[url.lastPathComponent] ?? VaultFileMetadata()
        let isPreviewing = audioPreview.playingPath == url.path && audioPreview.isPlaying
        let isAudio = VaultFileKinds.isPreviewableAudio(url)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: VaultFileKinds.symbol(for: url))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isAudio ? Theme.accent : (VaultFilter.sets.includes(url) ? Theme.violet : Theme.blue))
                .frame(width: 40, height: 40)
                .background((isAudio ? Theme.accent : (VaultFilter.sets.includes(url) ? Theme.violet : Theme.blue)).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    Text(fileSize(url))
                    Text("·")
                    Text(url.pathExtension.isEmpty ? "FILE" : url.pathExtension.uppercased())
                    if let date = modifiedDateOptional(url) {
                        Text("·")
                        Text(date, style: .date)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)

                metadataSummary(metadata)

                if !metadata.tagList.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(Array(metadata.tagList.prefix(4)), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Theme.accent.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button { editingTarget = FileEditTarget(fileURL: url) } label: {
                        Label(metadata.isEmpty ? "Add details" : "Edit details", systemImage: "tag")
                    }
                    .accessibilityLabel("Edit tags and music metadata")

                    Button { shareTarget = ShareTarget(url: url) } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export file")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.blue)
                .padding(.top, 3)
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                if isAudio {
                    Button { toggleAudio(url) } label: {
                        Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.background)
                            .frame(width: 34, height: 34)
                            .background(Theme.accent, in: Circle())
                    }
                    .accessibilityLabel(isPreviewing ? "Pause audio preview" : "Play audio preview")
                }

                Menu {
                    Button { editingTarget = FileEditTarget(fileURL: url) } label: { Label("Edit tags and notes", systemImage: "tag") }
                    Button { createSnapshot(of: url) } label: { Label("Create snapshot", systemImage: "archivebox") }
                    Button { shareTarget = ShareTarget(url: url) } label: { Label("Export / share", systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 34)
                }
                .accessibilityLabel("File actions")
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    @ViewBuilder
    private func metadataSummary(_ metadata: VaultFileMetadata) -> some View {
        let parts = [
            metadata.bpm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "\(metadata.bpm) BPM",
            metadata.musicalKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : metadata.musicalKey.trimmingCharacters(in: .whitespacesAndNewlines)
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: "  ·  "))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.warning)
                .lineLimit(1)
        } else if !metadata.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(metadata.notes)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        } else {
            EmptyView()
        }
    }

    private func backupFileRow(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(originalName(forBackup: url))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(fileSize(url))
                    if let date = backupDate(url) {
                        Text("·")
                        Text(date, style: .date)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Button { shareTarget = ShareTarget(url: url) } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .frame(width: 32, height: 36)
            }
            .accessibilityLabel("Export snapshot")
            Menu {
                Button { restoreBackup(url) } label: { Label("Restore to library", systemImage: "arrow.uturn.backward") }
                Button { shareTarget = ShareTarget(url: url) } label: { Label("Export snapshot", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { deleteTarget = url } label: { Label("Delete snapshot", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 36)
            }
            .accessibilityLabel("Snapshot actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func refresh() {
        do {
            try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            let supportFolder = metadataURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
            downloadedFiles = try listFiles(in: downloadsURL)
            backupFiles = try listFiles(in: backupsURL)
            loadMetadata()
        } catch {
            showMessage("Could not read the local file folders: \(error.localizedDescription)")
        }
    }

    private func listFiles(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == false
        }
        .sorted { modifiedDate($0) > modifiedDate($1) }
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: VaultFileMetadata].self, from: data) else {
            metadataByName = [:]
            return
        }
        metadataByName = decoded
    }

    private func persistMetadata() {
        do {
            let folder = metadataURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(metadataByName)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            showMessage("File details could not be saved: \(error.localizedDescription)")
        }
    }

    private func createSnapshot(of source: URL) {
        do {
            try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let requestedName = "\(formatter.string(from: Date()))__\(source.lastPathComponent)"
            let destination = uniqueURL(named: requestedName, in: backupsURL)
            try FileManager.default.copyItem(at: source, to: destination)
            if let metadata = metadataByName[source.lastPathComponent] {
                metadataByName[destination.lastPathComponent] = metadata
                persistMetadata()
            }
            refresh()
            showMessage("Snapshot saved: \(source.lastPathComponent)")
        } catch {
            showMessage("Could not create the snapshot: \(error.localizedDescription)")
        }
    }

    private func restoreBackup(_ backup: URL) {
        do {
            try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
            let requestedName = originalName(forBackup: backup)
            let destination = uniqueURL(named: requestedName, in: downloadsURL)
            try FileManager.default.copyItem(at: backup, to: destination)
            if let metadata = metadataByName[backup.lastPathComponent] {
                metadataByName[destination.lastPathComponent] = metadata
                persistMetadata()
            } else if let metadata = metadataByName[requestedName] {
                metadataByName[destination.lastPathComponent] = metadata
                persistMetadata()
            }
            refresh()
            showMessage("Restored a copy to the library as \(destination.lastPathComponent). It has not been uploaded to Move.")
        } catch {
            showMessage("Could not restore the snapshot: \(error.localizedDescription)")
        }
    }

    private func deleteBackup(_ backup: URL) {
        do {
            try FileManager.default.removeItem(at: backup)
            metadataByName.removeValue(forKey: backup.lastPathComponent)
            persistMetadata()
            refresh()
            showMessage("Snapshot deleted.")
        } catch {
            showMessage("Could not delete the snapshot: \(error.localizedDescription)")
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showMessage("Import was cancelled or failed: \(error.localizedDescription)")
        case .success(let urls):
            guard !urls.isEmpty else {
                showMessage("No files were selected. Try Import again and tap Open in Files.")
                return
            }
            do {
                try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
                var importedNames: [String] = []
                var failures: [String] = []
                for source in urls {
                    do {
                        let destination = uniqueURL(named: source.lastPathComponent, in: downloadsURL)
                        try copyImportedFile(from: source, to: destination)
                        importedNames.append(destination.lastPathComponent)
                    } catch {
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                refresh()
                if failures.isEmpty {
                    let names = importedNames.prefix(5).joined(separator: "\n")
                    showMessage("Imported \(importedNames.count) file(s).\n\(names)\(importedNames.count > 5 ? "\n…" : "")")
                } else {
                    let failureSummary = failures.prefix(3).joined(separator: "\n")
                    showMessage("Imported \(importedNames.count) file(s); \(failures.count) failed.\n\(failureSummary)")
                }
            } catch {
                refresh()
                showMessage("Could not prepare the import folder: \(error.localizedDescription)")
            }
        }
    }

    private func copyImportedFile(from source: URL, to destination: URL) throws {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw NSError(domain: "SchwungPocket.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected file provider did not return a readable file."])
        }
    }

    private func toggleAudio(_ url: URL) {
        do {
            try audioPreview.toggle(url)
        } catch {
            showMessage("This audio file could not be previewed on this iPhone: \(error.localizedDescription)")
        }
    }

    private func uniqueURL(named name: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let original = URL(fileURLWithPath: name)
            let ext = original.pathExtension
            let stem = original.deletingPathExtension().lastPathComponent
            let uniqueName = ext.isEmpty ? "\(stem) (\(suffix))" : "\(stem) (\(suffix)).\(ext)"
            candidate = folder.appendingPathComponent(uniqueName)
            suffix += 1
        }
        return candidate
    }

    private func fileSizeBytes(_ url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return Int64(size)
    }

    private func fileSize(_ url: URL) -> String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes(url), countStyle: .file)
    }

    private func modifiedDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func modifiedDateOptional(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func backupDate(_ url: URL) -> Date? {
        let prefix = url.lastPathComponent.components(separatedBy: "__").first ?? ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: prefix)
    }

    private func originalName(forBackup url: URL) -> String {
        let name = url.lastPathComponent
        guard let separator = name.range(of: "__") else { return name }
        return String(name[separator.upperBound...])
    }

    private func showMessage(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
}

private final class AudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingPath: String?
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?

    func toggle(_ url: URL) throws {
        if let current = player, current.url?.path == url.path {
            if isPlaying {
                current.pause()
                isPlaying = false
            } else {
                if current.play() {
                    isPlaying = true
                } else {
                    throw NSError(domain: "SchwungPocket.AudioPreview", code: 2, userInfo: [NSLocalizedDescriptionKey: "The audio player could not resume playback."])
                }
            }
            return
        }

        stop()
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        let nextPlayer = try AVAudioPlayer(contentsOf: url)
        nextPlayer.delegate = self
        nextPlayer.prepareToPlay()
        guard nextPlayer.play() else {
            throw NSError(domain: "SchwungPocket.AudioPreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "The audio player could not start playback."])
        }
        player = nextPlayer
        playingPath = url.path
        isPlaying = true
    }

    func stop() {
        player?.stop()
        player = nil
        playingPath = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ finishedPlayer: AVAudioPlayer, successfully flag: Bool) {
        guard player === finishedPlayer else { return }
        player = nil
        playingPath = nil
        isPlaying = false
    }
}

private struct FileMetadataEditor: View {
    let fileName: String
    let initialValue: VaultFileMetadata
    let onSave: (VaultFileMetadata) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: String
    @State private var bpm: String
    @State private var musicalKey: String
    @State private var notes: String

    init(fileName: String, initialValue: VaultFileMetadata, onSave: @escaping (VaultFileMetadata) -> Void) {
        self.fileName = fileName
        self.initialValue = initialValue
        self.onSave = onSave
        _tags = State(initialValue: initialValue.tags)
        _bpm = State(initialValue: initialValue.bpm)
        _musicalKey = State(initialValue: initialValue.musicalKey)
        _notes = State(initialValue: initialValue.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("FILE") {
                    Text(fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .textSelection(.enabled)
                }

                Section("MUSIC METADATA") {
                    TextField("Tempo in BPM", text: $bpm)
                        .keyboardType(.decimalPad)
                    TextField("Key (for example, C minor)", text: $musicalKey)
                        .textInputAutocapitalization(.words)
                    TextField("Tags, separated by commas", text: $tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Notes or sound-design ideas", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Text("Details are stored locally on this iPhone. Tags, tempo, key and notes are searchable in the library. They do not alter the audio file or Ableton Set itself.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("File Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanedTags = tags.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: ", ")
                        let value = VaultFileMetadata(
                            tags: cleanedTags,
                            bpm: bpm.trimmingCharacters(in: .whitespacesAndNewlines),
                            musicalKey: musicalKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(value)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct ShareTarget: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

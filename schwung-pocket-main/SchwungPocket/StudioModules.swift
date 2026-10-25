import SwiftUI
import UIKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Module registry

/// Independent modules shown as their own cards in the Modules tab.
/// To add a module: add a case, give it metadata, and return its screen from `destination`.
/// The Modules tab iterates `allCases`, so no navigation code needs to change.
enum PocketStudioModule: String, CaseIterable, Identifiable {
    case nativeControls, sampleLab, grooveToolkit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nativeControls: return "Native Controls"
        case .sampleLab: return "Sample Lab"
        case .grooveToolkit: return "Groove Toolkit"
        }
    }

    var subtitle: String {
        switch self {
        case .nativeControls: return "Live knobs and switches for Schwung instruments"
        case .sampleLab: return "Import, audition and shelve audio on this iPhone"
        case .grooveToolkit: return "Sketch a pattern and export it as MIDI"
        }
    }

    var symbol: String {
        switch self {
        case .nativeControls: return "dial.medium"
        case .sampleLab: return "waveform"
        case .grooveToolkit: return "circle.grid.3x3.fill"
        }
    }

    var tint: Color {
        switch self {
        case .nativeControls: return Theme.accent
        case .sampleLab: return Theme.blue
        case .grooveToolkit: return Theme.violet
        }
    }

    @ViewBuilder
    func destination(device: MoveConnectionStore) -> some View {
        switch self {
        case .nativeControls: NativeControlsScreen(device: device)
        case .sampleLab: SampleLabScreen()
        case .grooveToolkit: GrooveToolkitScreen()
        }
    }
}

/// One selectable module card for the Modules tab.
struct StudioModuleCard: View {
    let module: PocketStudioModule
    @ObservedObject var device: MoveConnectionStore

    var body: some View {
        NavigationLink {
            module.destination(device: device)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: module.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(module.tint)
                    .frame(width: 44, height: 44)
                    .background(module.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(module.title).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    Text(module.subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(module.tint)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(module.tint.opacity(0.22), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// Shared dedicated-screen chrome for every module. Pushed from the Modules tab's NavigationStack.
struct ModuleScreenShell<Content: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow).font(.system(size: 10, weight: .heavy)).tracking(1.8).foregroundStyle(Theme.accent)
                    Text(title).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                content
            }
            .padding(18)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct SampleLabScreen: View {
    var body: some View {
        ModuleScreenShell(eyebrow: "SCHWUNG POCKET / MODULE", title: "Sample Lab",
                          subtitle: "Import audio from Files and audition it on this iPhone.") {
            SampleLabView()
            Text("EXPERIMENTAL · Save your originals before testing workflows.")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct GrooveToolkitScreen: View {
    var body: some View {
        ModuleScreenShell(eyebrow: "SCHWUNG POCKET / MODULE", title: "Groove Toolkit",
                          subtitle: "Sketch a drum pattern and export it as a MIDI file.") {
            GrooveToolkitView()
            Text("EXPERIMENTAL · Save your originals before testing workflows.")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Sample Lab & Groove Toolkit (moved unchanged from ExperimentalStudio.swift, v0.8.1)

struct SampleLabView: View {
    @State private var samples: [LabSample] = []
    @State private var showingImporter = false
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var errorMessage: String?
    private var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SampleLab", isDirectory: true) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PocketCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Sample Lab", systemImage: "waveform").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    Text("Import audio from Files, audition it, and keep a lightweight local sample shelf on this iPhone.").font(.system(size: 13)).lineSpacing(3).foregroundStyle(Theme.muted)
                    Button { showingImporter = true } label: { Label("Import audio", systemImage: "plus.circle.fill").font(.system(size: 14, weight: .bold)) }.buttonStyle(StudioPrimaryButton())
                }
            }
            if let errorMessage { Text(errorMessage).font(.system(size: 12)).foregroundStyle(Theme.warning) }
            if samples.isEmpty {
                PocketCard { VStack(alignment: .leading, spacing: 7) { Image(systemName: "tray").font(.system(size: 25)).foregroundStyle(Theme.violet); Text("Your sample shelf is empty").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white); Text("Add WAV, AIFF, MP3, M4A or another audio format supported by iOS.").font(.system(size: 12)).foregroundStyle(Theme.muted) } }
            } else {
                ForEach(samples) { sample in
                    PocketCard {
                        HStack(spacing: 12) {
                            Button { audition(sample) } label: { Image(systemName: playingID == sample.id ? "stop.fill" : "play.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.background).frame(width: 42, height: 42).background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) { Text(sample.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(2); Text(sample.url.pathExtension.uppercased() + " · local file").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio], allowsMultipleSelection: true, onCompletion: importFiles)
        .onAppear(perform: loadSamples)
    }
    private func loadSamples() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        samples = urls.filter { !$0.hasDirectoryPath && $0.pathExtension.lowercased() != "json" }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }.map { LabSample(name: $0.deletingPathExtension().lastPathComponent, url: $0) }
    }
    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for source in urls {
                let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
                let safeName = source.lastPathComponent
                var destination = directory.appendingPathComponent(safeName)
                if FileManager.default.fileExists(atPath: destination.path) { destination = directory.appendingPathComponent(UUID().uuidString + "-" + safeName) }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            errorMessage = nil; loadSamples()
        } catch { errorMessage = "Import failed: \(error.localizedDescription)" }
    }
    private func audition(_ sample: LabSample) {
        if playingID == sample.id { player?.stop(); player = nil; playingID = nil; return }
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers]); try AVAudioSession.sharedInstance().setActive(true); player = try AVAudioPlayer(contentsOf: sample.url); player?.prepareToPlay(); player?.play(); playingID = sample.id }
        catch { errorMessage = "Can't preview this file: \(error.localizedDescription)" }
    }
}
private struct LabSample: Identifiable { let id = UUID(); let name: String; let url: URL }

struct GrooveToolkitView: View {
    @State private var bpm = 128.0
    @State private var swing = 0.12
    @State private var steps = Array(repeating: false, count: 16)
    @State private var exportURL: URL?
    @State private var message: String?
    private let rows = [("KICK", "circle.fill"), ("CLAP", "circle.grid.2x2.fill"), ("HAT", "circle")]
    @State private var kick = [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false]
    @State private var clap = [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false]
    @State private var hat = (0..<16).map { $0 % 2 == 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PocketCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Groove Toolkit", systemImage: "circle.grid.3x3.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    HStack { Text("TEMPO").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.muted); Spacer(); Text("\(Int(bpm)) BPM").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent) }
                    Slider(value: $bpm, in: 70...180, step: 1).tint(Theme.accent)
                    HStack { Text("SWING").font(.system(size: 10, weight: .heavy)).tracking(1.2).foregroundStyle(Theme.muted); Spacer(); Text("\(Int(swing * 100))%").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.accent) }
                    Slider(value: $swing, in: 0...0.45).tint(Theme.violet)
                }
            }
            grooveRow("KICK", pattern: $kick, tint: Theme.accent)
            grooveRow("CLAP", pattern: $clap, tint: Theme.violet)
            grooveRow("HAT", pattern: $hat, tint: Theme.blue)
            HStack(spacing: 8) {
                Button("Randomise") { randomise() }.buttonStyle(StudioSecondaryButton())
                Button("4-on-floor") { kick = (0..<16).map { $0 % 4 == 0 }; clap = (0..<16).map { $0 % 8 == 4 }; hat = (0..<16).map { $0 % 2 == 0 } }.buttonStyle(StudioSecondaryButton())
            }
            PocketCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("EXPORT MIDI").font(.system(size: 10, weight: .heavy)).tracking(1.3).foregroundStyle(Theme.muted)
                    Text("Export a one-bar, three-lane MIDI groove. Swing is applied to offbeat events. Import the MIDI into your DAW to audition and edit it.").font(.system(size: 12)).lineSpacing(3).foregroundStyle(Theme.muted)
                    Button { exportMIDI() } label: { Label("Create MIDI file", systemImage: "square.and.arrow.up").font(.system(size: 14, weight: .bold)) }.buttonStyle(StudioPrimaryButton())
                    if let exportURL { ShareLink(item: exportURL) { Label("Share \(exportURL.lastPathComponent)", systemImage: "arrowshape.turn.up.right").font(.system(size: 13, weight: .semibold)) }.tint(Theme.accent) }
                    if let message { Text(message).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }
            }
        }
    }
    private func grooveRow(_ title: String, pattern: Binding<[Bool]>, tint: Color) -> some View {
        PocketCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(title).font(.system(size: 11, weight: .heavy)).tracking(1.4).foregroundStyle(tint); Spacer(); Text("16 STEPS").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 8), spacing: 7) {
                    ForEach(0..<16, id: \.self) { i in
                        Button { pattern.wrappedValue[i].toggle() } label: {
                            Text("\(i + 1)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(pattern.wrappedValue[i] ? Theme.background : Theme.muted)
                                .frame(maxWidth: .infinity).frame(height: 34).background(pattern.wrappedValue[i] ? tint : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private func randomise() {
        kick = (0..<16).map { $0 % 4 == 0 || Int.random(in: 0..<100) < 8 }
        clap = (0..<16).map { $0 % 8 == 4 || Int.random(in: 0..<100) < 7 }
        hat = (0..<16).map { $0 % 2 == 0 || Int.random(in: 0..<100) < 35 }
    }
    private func exportMIDI() {
        let ticksPerQuarter = 480
        let ticksPerBar = ticksPerQuarter * 4
        let microseconds = Int(60_000_000 / bpm)
        var events: [(Int, [UInt8])] = []
        let tempo: [UInt8] = [0x00, 0xFF, 0x51, 0x03, UInt8((microseconds >> 16) & 255), UInt8((microseconds >> 8) & 255), UInt8(microseconds & 255)]
        events.append((0, tempo))
        let lanes: [([Bool], UInt8, UInt8)] = [(kick, 36, 9), (clap, 39, 9), (hat, 42, 9)]
        for (pattern, note, channel) in lanes {
            for index in 0..<16 where pattern[index] {
                var tick = index * (ticksPerBar / 16)
                if index % 2 == 1 { tick += Int(Double(ticksPerQuarter / 2) * swing) }
                events.append((tick, [0x00, UInt8(0x90 | channel), note, 100]))
                events.append((tick + 90, [0x00, UInt8(0x80 | channel), note, 0]))
            }
        }
        events.sort { $0.0 < $1.0 }
        var track: [UInt8] = []
        var lastTick = 0
        for (tick, bytes) in events {
            let delta = max(0, tick - lastTick); lastTick = tick
            let encoded = Self.variableLength(delta)
            track.append(contentsOf: encoded)
            if bytes.count == 7 && bytes[1] == 0xFF { track.append(contentsOf: Array(bytes.dropFirst())) }
            else { track.append(contentsOf: Array(bytes.dropFirst())) }
        }
        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])
        var data = Data("MThd".utf8); data.append(contentsOf: [0, 0, 0, 6, 0, 0, 0, 1, UInt8(ticksPerQuarter >> 8), UInt8(ticksPerQuarter & 255)])
        data.append(contentsOf: Array("MTrk".utf8)); let length = UInt32(track.count)
        data.append(contentsOf: [UInt8((length >> 24) & 255), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)]); data.append(contentsOf: track)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SchwungPocket-Groove-\(Int(bpm))bpm.mid")
        do { try data.write(to: url, options: .atomic); exportURL = url; message = "MIDI created. Use Share to save it to Files or send it to your DAW." }
        catch { message = "MIDI export failed: \(error.localizedDescription)" }
    }
    private static func variableLength(_ value: Int) -> [UInt8] {
        var buffer = value & 0x7F; var remaining = value >> 7
        while remaining > 0 { buffer <<= 8; buffer |= ((remaining & 0x7F) | 0x80); remaining >>= 7 }
        var result: [UInt8] = []
        while true { result.append(UInt8(buffer & 255)); if buffer & 0x80 != 0 { buffer >>= 8 } else { break } }
        return result
    }
}

struct StudioPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.foregroundStyle(Theme.background).padding(.horizontal, 14).padding(.vertical, 11).background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 12)) }
}
struct StudioSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 10).background(Theme.surfaceRaised.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 11)) }
}

import Foundation
import Combine

public class RemoteControlStore: ObservableObject {
    @Published public var selectedDestination: Destination = .slot1
    @Published public var parameters: [ParameterModel] = []
    @Published public var isConnected: Bool = false
    @Published public var activeInstrumentName: String = "303"
    @Published public var statusMessage: String = "Ready"

    public var groupedParameters: [String: [ParameterModel]] {
        Dictionary(grouping: parameters, by: { $0.groupName })
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?

    public init() {
        session = URLSession(configuration: .default)
        loadMockParameters(for: .slot1)
    }

    public func selectDestination(_ destination: Destination) {
        selectedDestination = destination
        loadMockParameters(for: destination)
    }

    public func updateParameter(_ id: String, value: String) {
        if let idx = parameters.firstIndex(where: { $0.id == id }) {
            if let fVal = Float(value) {
                parameters[idx].floatValue = fVal
            }
        }
    }

    private func loadMockParameters(for destination: Destination) {
        switch destination {
        case .slot1:
            activeInstrumentName = "303 Synthesizer"
            parameters = [
                ParameterModel(key: "synth:cutoff", name: "Cutoff", groupName: "Filter", type: .floatParam, floatValue: 0.45, minValue: 0.0, maxValue: 1.0, step: 0.01),
                ParameterModel(key: "synth:resonance", name: "Resonance", groupName: "Filter", type: .floatParam, floatValue: 0.70, minValue: 0.0, maxValue: 1.0, step: 0.01),
                ParameterModel(key: "synth:waveform", name: "Waveform", groupName: "Oscillator", type: .enumParam, enumValue: 0, options: ["Saw", "Square"])
            ]
        case .slot2:
            activeInstrumentName = "9w9 Drum Machine"
            parameters = [
                ParameterModel(key: "bd:tune", name: "BD Tune", groupName: "Bass Drum", type: .floatParam, floatValue: 0.50),
                ParameterModel(key: "sn:drive", name: "SN Drive", groupName: "Snare Drum", type: .floatParam, floatValue: 0.40)
            ]
        case .slot3:
            activeInstrumentName = "Sampler Module"
            parameters = [
                ParameterModel(key: "sample:pitch", name: "Pitch", groupName: "Playback", type: .floatParam, floatValue: 0.50)
            ]
        case .slot4:
            activeInstrumentName = "FM Synth"
            parameters = [
                ParameterModel(key: "fm:ratio", name: "Ratio", groupName: "FM Engine", type: .floatParam, floatValue: 0.25)
            ]
        case .masterFX, .tool:
            activeInstrumentName = destination.rawValue
            parameters = []
        }
    }
}
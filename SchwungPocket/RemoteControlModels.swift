import Foundation

public enum ControlDestination: String, CaseIterable, Identifiable {
    case slot1 = "Slot 1"
    case slot2 = "Slot 2"
    case slot3 = "Slot 3"
    case slot4 = "Slot 4"
    case masterFx = "Master FX"
    case tool = "Tool"

    public var id: String { rawValue }

    public var wireSlotIndex: Int? {
        switch self {
        case .slot1: return 0 // Centrally maps UI Slot 1 to Wire Slot 0
        case .slot2: return 1
        case .slot3: return 2
        case .slot4: return 3
        case .masterFx, .tool: return nil // Master FX and Tool use direct endpoints/custom protocol
        }
    }
}

public enum ParameterType: String, Codable {
    case float
    case integer = "int"
    case enumType = "enum"
    case filepath
    case initType = "init"
    case canvas
    case unknown
}

public struct RemoteParameter: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let type: ParameterType
    public var value: String
    public let options: [String]
    public let min: Float
    public let max: Float
    public let group: String

    public init(
        id: String,
        name: String,
        type: ParameterType = .float,
        value: String = "0",
        options: [String] = [],
        min: Float = 0.0,
        max: Float = 1.0,
        group: String = "General"
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.value = value
        self.options = options
        self.min = min
        self.max = max
        self.group = group
    }
}

public struct SlotHierarchy {
    public let slot: Int
    public let component: String
    public let groups: [String: [String]]
}

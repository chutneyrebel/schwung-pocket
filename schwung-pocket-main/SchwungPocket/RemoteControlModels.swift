import Foundation

public enum Destination: String, CaseIterable, Identifiable {
    case slot1 = "Slot 1"
    case slot2 = "Slot 2"
    case slot3 = "Slot 3"
    case slot4 = "Slot 4"
    case masterFX = "Master FX"
    case tool = "Tool"

    public var id: String { rawValue }

    public var slotIndex: Int {
        switch self {
        case .slot1: return 1
        case .slot2: return 2
        case .slot3: return 3
        case .slot4: return 4
        case .masterFX: return 5
        case .tool: return 6
        }
    }
}

public enum ParameterType: String, Codable {
    case floatParam = "float"
    case enumParam = "enum"
    case filepathParam = "filepath"
    case canvasParam = "canvas"
    case initParam = "init"
    case unknown
}

public struct ParameterModel: Identifiable, Hashable {
    public let id: String
    public let key: String
    public let name: String
    public let groupName: String
    public let type: ParameterType
    public var floatValue: Float
    public var enumValue: Int
    public let options: [String]
    public let minValue: Float
    public let maxValue: Float
    public let step: Float
    public let isReadOnly: Bool

    public init(id: String = UUID().uuidString,
                key: String,
                name: String,
                groupName: String = "General",
                type: ParameterType = .floatParam,
                floatValue: Float = 0.0,
                enumValue: Int = 0,
                options: [String] = [],
                minValue: Float = 0.0,
                maxValue: Float = 1.0,
                step: Float = 0.01,
                isReadOnly: Bool = false) {
        self.id = id
        self.key = key
        self.name = name
        self.groupName = groupName
        self.type = type
        self.floatValue = floatValue
        self.enumValue = enumValue
        self.options = options
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.isReadOnly = isReadOnly
    }
}
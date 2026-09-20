import CoreGraphics

enum HyperKey: String, CaseIterable, Sendable {
    case rightOption = "right_option"
    case leftOption = "left_option"
    case rightControl = "right_control"
    case leftControl = "left_control"
    case rightCommand = "right_command"
    case leftCommand = "left_command"

    var keyCode: CGKeyCode {
        switch self {
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightControl: return 62
        case .leftControl: return 59
        case .rightCommand: return 54
        case .leftCommand: return 55
        }
    }

    var displayName: String {
        rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}

enum KeyCodes {
    private static let namesByCode: [CGKeyCode: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 36: "return",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space",
        50: "`", 51: "delete", 53: "escape",
    ]

    private static let codesByName = Dictionary(uniqueKeysWithValues: namesByCode.map { ($1, $0) })

    static func name(for code: CGKeyCode) -> String? {
        namesByCode[code]
    }

    static func code(for name: String) -> CGKeyCode? {
        codesByName[name]
    }
}

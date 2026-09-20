import Foundation

struct Binding: Equatable, Sendable {
    let key: String
    let app: String
}

struct Configuration: Equatable, Sendable {
    var hyperKey: HyperKey?
    var bindings: [Binding]
}

enum ConfigError: LocalizedError {
    case invalidLine(Int, String)
    case missingValue(Int, String)
    case duplicateBinding(String)

    var errorDescription: String? {
        switch self {
        case let .invalidLine(line, message):
            return "Invalid config at line \(line): \(message)"
        case let .missingValue(line, value):
            return "Missing \(value) for binding starting at line \(line)"
        case let .duplicateBinding(key):
            return "Duplicate binding for key '\(key)'"
        }
    }
}

enum ConfigStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/kvinta", isDirectory: true)
    static let file = directory.appendingPathComponent("config.toml")

    static func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return Configuration(hyperKey: nil, bindings: [])
        }

        let contents = try String(contentsOf: file, encoding: .utf8)
        var hyperKey: HyperKey?
        var bindings: [Binding] = []
        var bindingStart: Int?
        var bindingKey: String?
        var bindingApp: String?

        func finishBinding() throws {
            guard let start = bindingStart else { return }
            guard let key = bindingKey else { throw ConfigError.missingValue(start, "key") }
            guard let app = bindingApp else { throw ConfigError.missingValue(start, "app") }
            let normalizedKey = key.lowercased()
            guard KeyCodes.code(for: normalizedKey) != nil else {
                throw ConfigError.invalidLine(start, "unsupported key '\(key)'")
            }
            guard !bindings.contains(where: { $0.key == normalizedKey }) else {
                throw ConfigError.duplicateBinding(normalizedKey)
            }
            bindings.append(Binding(key: normalizedKey, app: app))
        }

        for (index, originalLine) in contents.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let line = stripComment(from: originalLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line == "[[bindings]]" {
                try finishBinding()
                bindingStart = lineNumber
                bindingKey = nil
                bindingApp = nil
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                throw ConfigError.invalidLine(lineNumber, "expected key = \"value\"")
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            let value = try parseString(rawValue, line: lineNumber)

            if bindingStart != nil {
                switch name {
                case "key": bindingKey = value
                case "app": bindingApp = value
                default: throw ConfigError.invalidLine(lineNumber, "unknown binding field '\(name)'")
                }
            } else {
                guard name == "hyper_key" else {
                    throw ConfigError.invalidLine(lineNumber, "unknown field '\(name)'")
                }
                guard let parsed = HyperKey(rawValue: value) else {
                    throw ConfigError.invalidLine(lineNumber, "unsupported Hyper key '\(value)'")
                }
                hyperKey = parsed
            }
        }

        try finishBinding()
        return Configuration(hyperKey: hyperKey, bindings: bindings)
    }

    static func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var lines = ["# After editing this file manually, run 'kvinta reload' to apply your changes."]
        if let hyperKey = configuration.hyperKey {
            lines.append("hyper_key = \"\(hyperKey.rawValue)\"")
        }
        for binding in configuration.bindings {
            lines.append("")
            lines.append("[[bindings]]")
            lines.append("key = \"\(escape(binding.key))\"")
            lines.append("app = \"\(escape(binding.app))\"")
        }
        lines.append("")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private static func stripComment(from line: String) -> String {
        var escaped = false
        var quoted = false
        for index in line.indices {
            let character = line[index]
            if character == "\\" && quoted {
                escaped.toggle()
                continue
            }
            if character == "\"" && !escaped { quoted.toggle() }
            if character == "#" && !quoted { return String(line[..<index]) }
            escaped = false
        }
        return line
    }

    private static func parseString(_ raw: String, line: Int) throws -> String {
        guard raw.first == "\"", raw.last == "\"", raw.count >= 2 else {
            throw ConfigError.invalidLine(line, "values must be double-quoted strings")
        }
        do {
            let data = Data("[\(raw)]".utf8)
            guard let values = try JSONSerialization.jsonObject(with: data) as? [String],
                  let value = values.first else {
                throw ConfigError.invalidLine(line, "invalid string")
            }
            return value
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.invalidLine(line, "invalid quoted string")
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

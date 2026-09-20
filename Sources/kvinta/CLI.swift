import Foundation

enum CLIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): return message
        }
    }
}

enum CLI {
    static let version = "0.1.1"

    static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "key": try chooseHyperKey()
        case "add": try addBinding()
        case "info": try printInfo()
        case "daemon": try Daemon.run()
        case "version", "--version", "-v": print("kvinta \(version)")
        case "help", "--help", "-h": printHelp()
        default: throw CLIError.message("Unknown command '\(command)'. Run 'kvinta help'.")
        }
    }

    private static func printInfo() throws {
        let configuration = try ConfigStore.load()
        let applications = Dictionary(uniqueKeysWithValues: Applications.installed().map {
            ($0.bundleIdentifier, $0.name)
        })

        print("Version: \(version)")
        print("Hyper key: \(configuration.hyperKey?.displayName ?? "Not configured")")
        print("Bindings:")
        if configuration.bindings.isEmpty {
            print("  None")
        } else {
            for binding in configuration.bindings {
                let application = applications[binding.app].map { "\($0) (\(binding.app))" } ?? binding.app
                print("  Hyper + \(binding.key.uppercased()) -> \(application)")
            }
        }
    }

    private static func chooseHyperKey() throws {
        print("Choose the physical key to use as Hyper:\n")
        let choices = HyperKey.allCases
        for (index, key) in choices.enumerated() {
            print("  \(index + 1). \(key.displayName)")
        }
        let selected = try selectIndex(count: choices.count, prompt: "\nSelection")

        var configuration = try ConfigStore.load()
        configuration.hyperKey = choices[selected]
        try ConfigStore.save(configuration)
        print("\nHyper key set to \(choices[selected].displayName).")

        guard AccessibilityPermission.request() else {
            print("Grant Accessibility permission. The background process will start automatically.")
            return
        }
        try Daemon.reloadOrStart()
        print("Background process is running.")
    }

    private static func addBinding() throws {
        var configuration = try ConfigStore.load()
        guard let hyperKey = configuration.hyperKey else {
            throw CLIError.message("No Hyper key configured. Run 'kvinta key' first.")
        }
        guard AccessibilityPermission.request() else { throw KeyboardError.accessibilityRequired }

        var daemonPaused = Daemon.pauseForCapture()
        defer {
            if daemonPaused { Daemon.resumeAfterCapture() }
        }

        print("Press your shortcut (\(hyperKey.displayName) + key)...")
        let key = try ShortcutCapture.capture(hyperKey: hyperKey)
        if daemonPaused {
            Daemon.resumeAfterCapture()
            daemonPaused = false
        }
        print("Captured Hyper + \(key.uppercased()).")

        let application = try chooseApplication(from: Applications.installed())
        let binding = Binding(key: key, app: application.bundleIdentifier)
        if let index = configuration.bindings.firstIndex(where: { $0.key == key }) {
            configuration.bindings[index] = binding
        } else {
            configuration.bindings.append(binding)
        }
        try ConfigStore.save(configuration)
        try Daemon.reloadOrStart()
        print("Hyper + \(key.uppercased()) now toggles \(application.name).")
    }

    private static func chooseApplication(from applications: [ApplicationCandidate]) throws -> ApplicationCandidate {
        guard !applications.isEmpty else {
            throw CLIError.message("No applications were found.")
        }

        while true {
            print("\nSearch applications (leave empty to show all): ", terminator: "")
            guard let query = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw CLIError.message("Application selection cancelled.")
            }
            let matches = query.isEmpty ? applications : applications.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
            }
            guard !matches.isEmpty else {
                print("No matching applications.")
                continue
            }
            guard matches.count <= 30 else {
                print("\(matches.count) matches. Enter a more specific search.")
                continue
            }

            for (index, application) in matches.enumerated() {
                print("  \(index + 1). \(application.name) (\(application.bundleIdentifier))")
            }
            let selected = try selectIndex(count: matches.count, prompt: "\nSelection")
            return matches[selected]
        }
    }

    private static func selectIndex(count: Int, prompt: String) throws -> Int {
        while true {
            print("\(prompt): ", terminator: "")
            guard let input = readLine() else { throw CLIError.message("Selection cancelled.") }
            if let value = Int(input), (1...count).contains(value) { return value - 1 }
            print("Enter a number from 1 to \(count).")
        }
    }

    private static func printHelp() {
        print("""
        Usage: kvinta <command>

          key    Choose the physical Hyper key
          add    Capture a Hyper shortcut and choose an application
          info   Show version, Hyper key, and bindings
          version  Show the installed version
        """)
    }
}

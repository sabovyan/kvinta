import AppKit
import Foundation

struct ApplicationCandidate {
    let name: String
    let bundleIdentifier: String
}

enum Applications {
    static func installed() -> [ApplicationCandidate] {
        var candidates: [String: ApplicationCandidate] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard let identifier = app.bundleIdentifier else { continue }
            let name = app.localizedName ?? identifier
            candidates[identifier] = ApplicationCandidate(name: name, bundleIdentifier: identifier)
        }

        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isApplicationKey]

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                candidates[identifier] = ApplicationCandidate(name: name, bundleIdentifier: identifier)
            }
        }

        return candidates.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func toggle(bundleIdentifier: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated })

        if let running {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier {
                running.hide()
            } else {
                running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            fputs("kvinta: application not found: \(bundleIdentifier)\n", stderr)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                fputs("kvinta: failed to launch \(bundleIdentifier): \(error.localizedDescription)\n", stderr)
            }
        }
    }
}

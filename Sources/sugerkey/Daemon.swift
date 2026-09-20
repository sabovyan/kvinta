import AppKit
import CoreGraphics
import Darwin
import Foundation

private final class DaemonContext {
    var configuration: Configuration
    var hyperDown = false
    var suppressedKeys: Set<CGKeyCode> = []
    var eventTap: CFMachPort?
    var pauseGeneration = 0

    init(configuration: Configuration) {
        self.configuration = configuration
    }
}

private func daemonCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<DaemonContext>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = context.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    guard let hyperKey = context.configuration.hyperKey else {
        return Unmanaged.passUnretained(event)
    }
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .flagsChanged, keyCode == hyperKey.keyCode {
        context.hyperDown.toggle()
        return nil
    }

    if type == .keyDown, context.hyperDown {
        context.suppressedKeys.insert(keyCode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           let key = KeyCodes.name(for: keyCode),
           let binding = context.configuration.bindings.first(where: { $0.key == key }) {
            Applications.toggle(bundleIdentifier: binding.app)
        }
        return nil
    }

    if type == .keyUp, context.suppressedKeys.remove(keyCode) != nil {
        return nil
    }

    return Unmanaged.passUnretained(event)
}

enum Daemon {
    static let launchAgentLabel = "com.sargisabovyan.sugerkey.daemon"
    static let launchAgentFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")

    static func run() throws -> Never {
        if !AccessibilityPermission.request() {
            fputs("sugerkey: waiting for Accessibility permission\n", stderr)
            while !AccessibilityPermission.isGranted {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            }
        }
        let configuration = try ConfigStore.load()
        guard configuration.hyperKey != nil else {
            throw CLIError.message("No Hyper key configured. Run 'sugerkey key' first.")
        }
        try FileManager.default.createDirectory(
            at: ConfigStore.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let context = DaemonContext(configuration: configuration)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask([.flagsChanged, .keyDown, .keyUp]),
            callback: daemonCallback,
            userInfo: pointer
        ) else {
            throw KeyboardError.eventTapUnavailable
        }
        context.eventTap = tap

        try String(getpid()).write(to: ConfigStore.pidFile, atomically: true, encoding: .utf8)
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        signal(SIGHUP, SIG_IGN)
        let reloadSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
        reloadSource.setEventHandler {
            do {
                context.configuration = try ConfigStore.load()
                context.hyperDown = false
                context.suppressedKeys.removeAll()
                context.pauseGeneration += 1
                CGEvent.tapEnable(tap: tap, enable: true)
            } catch {
                fputs("sugerkey: config reload failed: \(error.localizedDescription)\n", stderr)
            }
        }
        reloadSource.resume()

        signal(SIGUSR1, SIG_IGN)
        let pauseSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        pauseSource.setEventHandler {
            context.hyperDown = false
            context.suppressedKeys.removeAll()
            context.pauseGeneration += 1
            let generation = context.pauseGeneration
            CGEvent.tapEnable(tap: tap, enable: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                guard context.pauseGeneration == generation else { return }
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        pauseSource.resume()

        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let terminate = {
            try? FileManager.default.removeItem(at: ConfigStore.pidFile)
            exit(EXIT_SUCCESS)
        }
        terminateSource.setEventHandler(handler: terminate)
        interruptSource.setEventHandler(handler: terminate)
        terminateSource.resume()
        interruptSource.resume()

        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
        fatalError("Daemon run loop exited unexpectedly")
    }

    static func runningPID() -> pid_t? {
        guard let value = try? String(contentsOf: ConfigStore.pidFile, encoding: .utf8),
              let pid = pid_t(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0 else {
            try? FileManager.default.removeItem(at: ConfigStore.pidFile)
            return nil
        }
        return pid
    }

    static func reloadOrStart() throws {
        if let pid = runningPID() {
            kill(pid, SIGHUP)
            return
        }

        if FileManager.default.fileExists(atPath: launchAgentFile.path) {
            let launchctl = Process()
            launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            launchctl.arguments = ["kickstart", "-k", "gui/\(getuid())/\(launchAgentLabel)"]
            launchctl.standardInput = FileHandle.nullDevice
            launchctl.standardOutput = FileHandle.nullDevice
            launchctl.standardError = FileHandle.nullDevice
            try launchctl.run()
            launchctl.waitUntilExit()
        } else {
            guard let executable = Bundle.main.executableURL else {
                throw CLIError.message("Unable to locate the sugerkey executable.")
            }
            let process = Process()
            process.executableURL = executable
            process.arguments = ["daemon"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        for _ in 0..<20 {
            if runningPID() != nil { return }
            usleep(50_000)
        }
        throw CLIError.message("The background process did not start. Run 'sugerkey daemon' to see the error.")
    }

    static func pauseForCapture() -> Bool {
        guard let pid = runningPID() else { return false }
        guard kill(pid, SIGUSR1) == 0 else { return false }
        usleep(100_000)
        return true
    }

    static func resumeAfterCapture() {
        guard let pid = runningPID() else { return }
        kill(pid, SIGHUP)
    }

    static func stop() -> Bool {
        guard let pid = runningPID() else { return false }
        kill(pid, SIGTERM)
        for _ in 0..<20 {
            if kill(pid, 0) != 0 { return true }
            usleep(50_000)
        }
        return false
    }
}

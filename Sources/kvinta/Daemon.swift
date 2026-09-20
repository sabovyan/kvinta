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
    static let launchAgentLabel = "com.sargisabovyan.kvinta.daemon"
    static let launchAgentFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    static let launchAgentTarget = "gui/\(getuid())/\(launchAgentLabel)"

    static func run() throws -> Never {
        if !AccessibilityPermission.request() {
            fputs("kvinta: waiting for Accessibility permission\n", stderr)
            while !AccessibilityPermission.isGranted {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            }
        }
        let configuration = try ConfigStore.load()
        guard configuration.hyperKey != nil else {
            throw CLIError.message("No Hyper key configured. Run 'kvinta key' first.")
        }
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
                fputs("kvinta: config reload failed: \(error.localizedDescription)\n", stderr)
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
        let terminate = { () -> Void in exit(EXIT_SUCCESS) }
        terminateSource.setEventHandler(handler: terminate)
        interruptSource.setEventHandler(handler: terminate)
        terminateSource.resume()
        interruptSource.resume()

        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
        fatalError("Daemon run loop exited unexpectedly")
    }

    static func reloadOrStart() throws {
        if sendSignal("SIGHUP") { return }

        guard FileManager.default.fileExists(atPath: launchAgentFile.path) else {
            throw CLIError.message("Background process is not installed. Run './scripts/install.sh'.")
        }
        guard launchctl(["kickstart", "-k", launchAgentTarget]) else {
            throw CLIError.message("The background process did not start. Run './scripts/install.sh' again.")
        }
        usleep(100_000)
        guard sendSignal("SIGHUP") else {
            throw CLIError.message("The background process exited during startup. Check ~/Library/Logs/Kvinta.log.")
        }
    }

    static func pauseForCapture() -> Bool {
        guard sendSignal("SIGUSR1") else { return false }
        usleep(100_000)
        return true
    }

    static func resumeAfterCapture() {
        _ = sendSignal("SIGHUP")
    }

    private static func sendSignal(_ name: String) -> Bool {
        launchctl(["kill", name, launchAgentTarget])
    }

    private static func launchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

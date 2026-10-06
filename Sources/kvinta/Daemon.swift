import AppKit
import CoreGraphics
import Darwin
import Foundation

final class DaemonContext: NSObject {
    var configuration: Configuration
    var suppressedKeys: Set<CGKeyCode> = []
    let toggleApplication: (String) -> Void
    var eventTap: CFMachPort?
    var pauseGeneration = 0
    private(set) var userPaused = false
    private(set) var capturePaused = false
    private var statusItem: NSStatusItem?
    private var stateMenuItem: NSMenuItem?
    private var pauseMenuItem: NSMenuItem?

    var shouldIntercept: Bool { !userPaused && !capturePaused }

    init(configuration: Configuration, toggleApplication: @escaping (String) -> Void = Applications.toggle) {
        self.configuration = configuration
        self.toggleApplication = toggleApplication
        super.init()
    }

    func installMenuBarItem() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        let quitItem = NSMenuItem(title: "Quit Kvinta", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.menu = menu
        statusItem = item
        stateMenuItem = stateItem
        pauseMenuItem = pauseItem
        updateEventTap()
    }

    @objc func togglePause() {
        setUserPaused(!userPaused)
    }

    func setUserPaused(_ paused: Bool) {
        userPaused = paused
        updateEventTap()
    }

    func pauseForCapture() {
        capturePaused = true
        pauseGeneration += 1
        let generation = pauseGeneration
        updateEventTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.finishCapturePause(generation: generation)
        }
    }

    func finishCapturePause(generation: Int) {
        guard pauseGeneration == generation else { return }
        capturePaused = false
        updateEventTap()
    }

    func reload(configuration: Configuration) {
        self.configuration = configuration
        capturePaused = false
        pauseGeneration += 1
        updateEventTap()
    }

    func updateEventTap() {
        if !shouldIntercept { suppressedKeys.removeAll() }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: shouldIntercept) }
        let state = userPaused ? "Shortcuts paused" : capturePaused ? "Capturing shortcut" : "Shortcuts active"
        stateMenuItem?.title = state
        pauseMenuItem?.title = userPaused ? "Resume" : "Pause"
        if let button = statusItem?.button {
            let active = shouldIntercept
            let image = NSImage(named: NSImage.applicationIconName).map { icon in
                NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
                    icon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: 1)
                    let badge = NSBezierPath(ovalIn: NSRect(x: 9, y: 0, width: 9, height: 9))
                    (active ? NSColor.systemGreen : NSColor.systemGray).setFill()
                    badge.fill()
                    NSColor.white.setStroke()
                    NSColor.white.setFill()
                    if active {
                        let check = NSBezierPath()
                        check.move(to: NSPoint(x: 11, y: 4.5))
                        check.line(to: NSPoint(x: 13, y: 2.5))
                        check.line(to: NSPoint(x: 16, y: 6.5))
                        check.lineWidth = 1.2
                        check.lineCapStyle = .round
                        check.lineJoinStyle = .round
                        check.stroke()
                    } else {
                        NSBezierPath(roundedRect: NSRect(x: 11.5, y: 2, width: 1.3, height: 5), xRadius: 0.4, yRadius: 0.4).fill()
                        NSBezierPath(roundedRect: NSRect(x: 14.2, y: 2, width: 1.3, height: 5), xRadius: 0.4, yRadius: 0.4).fill()
                    }
                    return true
                }
            }
            image?.isTemplate = false
            button.image = image
            button.title = image == nil ? "K" : ""
            button.toolTip = "Kvinta — \(state)"
            button.setAccessibilityLabel("Kvinta — \(state)")
        }
    }

    @objc func quit() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        exit(EXIT_SUCCESS)
    }
}

func daemonCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<DaemonContext>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Releases may have been missed while the tap was disabled. Fail open
        // until a fresh key-down rather than retaining stale consumed presses.
        context.suppressedKeys.removeAll()
        context.updateEventTap()
        return Unmanaged.passUnretained(event)
    }

    guard context.shouldIntercept else {
        return Unmanaged.passUnretained(event)
    }
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .keyUp, context.suppressedKeys.remove(keyCode) != nil {
        return nil
    }

    if type == .keyDown {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return context.suppressedKeys.contains(keyCode) ? nil : Unmanaged.passUnretained(event)
        }
        // A fresh press also reconciles a release missed before this event.
        context.suppressedKeys.remove(keyCode)
    }

    guard let hyperKey = context.configuration.hyperKey else {
        return Unmanaged.passUnretained(event)
    }

    if type == .flagsChanged, keyCode == hyperKey.keyCode {
        return nil
    }

    if type == .keyDown, hyperKey.isPressed(in: event.flags),
       let key = KeyCodes.name(for: keyCode),
       let binding = context.configuration.bindings.first(where: { $0.key == key }) {
        context.suppressedKeys.insert(keyCode)
        context.toggleApplication(binding.app)
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
        signal(SIGHUP, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)
        signal(SIGCONT, SIG_IGN)
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
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
        context.installMenuBarItem()

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        let reloadSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
        reloadSource.setEventHandler {
            do {
                context.reload(configuration: try ConfigStore.load())
            } catch {
                fputs("kvinta: config reload failed: \(error.localizedDescription)\n", stderr)
            }
        }
        reloadSource.resume()

        signal(SIGUSR1, SIG_IGN)
        let pauseSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        pauseSource.setEventHandler {
            context.pauseForCapture()
        }
        pauseSource.resume()

        let userPauseSource = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        userPauseSource.setEventHandler {
            context.setUserPaused(true)
        }
        userPauseSource.resume()

        let userResumeSource = DispatchSource.makeSignalSource(signal: SIGCONT, queue: .main)
        userResumeSource.setEventHandler {
            context.setUserPaused(false)
        }
        userResumeSource.resume()

        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let terminate = { () -> Void in context.quit() }
        terminateSource.setEventHandler(handler: terminate)
        interruptSource.setEventHandler(handler: terminate)
        terminateSource.resume()
        interruptSource.resume()

        withExtendedLifetime((context, reloadSource, pauseSource, userPauseSource, userResumeSource, terminateSource, interruptSource)) {
            application.run()
        }
        fatalError("Daemon run loop exited unexpectedly")
    }

    static func reloadOrStart() throws {
        if sendSignal("SIGHUP") { return }
        // A new daemon loads configuration during startup. Sending SIGHUP here
        // can terminate it before its signal handler has been installed.
        try start()
    }

    static func start() throws {
        guard FileManager.default.fileExists(atPath: launchAgentFile.path) else {
            throw CLIError.message("Background process is not installed. Run './scripts/install.sh'.")
        }
        guard launchctl(["kickstart", launchAgentTarget]) else {
            throw CLIError.message("The background process did not start. Run './scripts/install.sh' again.")
        }
    }

    static func stop() throws {
        guard sendSignal("SIGTERM") else {
            throw CLIError.message("Could not stop Kvinta. The background process may not be running.")
        }
    }

    static func pause() throws {
        guard sendSignal("SIGUSR2") else {
            throw CLIError.message("Could not pause Kvinta. The background process may not be running.")
        }
    }

    static func resume() throws {
        guard sendSignal("SIGCONT") else {
            throw CLIError.message("Could not resume Kvinta. The background process may not be running.")
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

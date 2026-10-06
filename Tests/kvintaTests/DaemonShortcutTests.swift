import CoreGraphics
import Testing
@testable import kvinta

@MainActor
struct DaemonShortcutTests {
    private let hyperFlags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)
    private let configuration = Configuration(hyperKey: .rightOption, bindings: [Binding(key: "e", app: "test.app")])

    // Invoke only the callback: no event tap, posted keyboard events, or app operations.
    private func deliver(_ type: CGEventType, key: CGKeyCode, flags: CGEventFlags, repeatKey: Bool = false, to context: DaemonContext) throws -> Bool {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type == .keyDown))
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        let proxy = try #require(OpaquePointer(bitPattern: 1))
        let result = daemonCallback(proxy: proxy, type: type, event: event, userInfo: Unmanaged.passUnretained(context).toOpaque())
        if let result {
            #expect(result.takeUnretainedValue() === event)
            #expect(event.flags == flags)
        }
        return result == nil
    }

    @Test func unboundAndUnknownKeysPassThroughWithTheirFlags() throws {
        var actions: [String] = []
        let context = DaemonContext(configuration: configuration, toggleApplication: { actions.append($0) })
        for key: CGKeyCode in [0, 122] {
            #expect(try !deliver(.keyDown, key: key, flags: hyperFlags, to: context))
            #expect(try !deliver(.keyDown, key: key, flags: hyperFlags, repeatKey: true, to: context))
            #expect(try !deliver(.keyUp, key: key, flags: [], to: context))
        }
        #expect(context.suppressedKeys.isEmpty)
        #expect(actions.isEmpty)
    }

    @Test(arguments: [false, true]) func boundPressRemainsBalancedForEitherReleaseOrder(hyperReleasedFirst: Bool) throws {
        var actions: [String] = []
        let context = DaemonContext(configuration: configuration, toggleApplication: { actions.append($0) })
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, repeatKey: true, to: context))
        if hyperReleasedFirst {
            #expect(try deliver(.flagsChanged, key: 61, flags: [], to: context))
            #expect(try deliver(.keyDown, key: 14, flags: [], repeatKey: true, to: context))
        }
        #expect(try deliver(.keyUp, key: 14, flags: hyperReleasedFirst ? [] : hyperFlags, to: context))
        if !hyperReleasedFirst {
            #expect(try deliver(.flagsChanged, key: 61, flags: [], to: context))
        }
        #expect(actions == ["test.app"])
        #expect(context.suppressedKeys.isEmpty)
        #expect(try !deliver(.keyUp, key: 14, flags: [], to: context))
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        #expect(actions == ["test.app", "test.app"])
    }

    @Test func pressingHyperAfterAPassThroughDownDoesNotConsumeRepeatOrRelease() throws {
        var actions: [String] = []
        let context = DaemonContext(configuration: configuration, toggleApplication: { actions.append($0) })
        #expect(try !deliver(.keyDown, key: 14, flags: [], to: context))
        #expect(try deliver(.flagsChanged, key: 61, flags: hyperFlags, to: context))
        #expect(try !deliver(.keyDown, key: 14, flags: hyperFlags, repeatKey: true, to: context))
        #expect(try !deliver(.keyUp, key: 14, flags: hyperFlags, to: context))
        #expect(actions.isEmpty)
        #expect(context.suppressedKeys.isEmpty)
    }

    @Test func reloadPreservesConsumedPressWithoutAdoptingPassedPress() throws {
        var actions: [String] = []
        let context = DaemonContext(configuration: configuration, toggleApplication: { actions.append($0) })
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        #expect(try !deliver(.keyDown, key: 0, flags: hyperFlags, to: context))
        context.reload(configuration: Configuration(hyperKey: .leftControl, bindings: [Binding(key: "a", app: "other.app")]))
        let controlFlags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x1)
        #expect(try deliver(.keyDown, key: 14, flags: controlFlags, repeatKey: true, to: context))
        #expect(try !deliver(.keyDown, key: 0, flags: controlFlags, repeatKey: true, to: context))
        #expect(try deliver(.keyUp, key: 14, flags: [], to: context))
        #expect(try !deliver(.keyUp, key: 0, flags: [], to: context))
        #expect(actions == ["test.app"])
        #expect(context.suppressedKeys.isEmpty)
        #expect(try deliver(.keyDown, key: 0, flags: controlFlags, to: context))
        #expect(actions == ["test.app", "other.app"])
    }

    @Test func removingHyperDuringReloadStillConsumesOriginalRelease() throws {
        let context = DaemonContext(configuration: configuration, toggleApplication: { _ in })
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        context.reload(configuration: Configuration(hyperKey: nil, bindings: []))
        #expect(try deliver(.keyDown, key: 14, flags: [], repeatKey: true, to: context))
        #expect(try deliver(.keyUp, key: 14, flags: [], to: context))
        #expect(context.suppressedKeys.isEmpty)
    }

    @Test(arguments: [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput]) func recoveryClearsStalePressAndDoesNotAdoptRepeats(type: CGEventType) throws {
        var actions: [String] = []
        let context = DaemonContext(configuration: configuration, toggleApplication: { actions.append($0) })
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        #expect(try !deliver(type, key: 14, flags: [], to: context))
        #expect(context.suppressedKeys.isEmpty)
        #expect(try !deliver(.keyDown, key: 14, flags: hyperFlags, repeatKey: true, to: context))
        #expect(try !deliver(.keyUp, key: 14, flags: [], to: context))
        #expect(actions == ["test.app"])
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        #expect(actions == ["test.app", "test.app"])
    }

    @Test func pauseClearsTrackingAndResumeDoesNotAdoptHeldKeys() throws {
        var actions: [String] = []
        let context = DaemonContext(configuration: configuration, toggleApplication: { actions.append($0) })
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        context.setUserPaused(true)
        #expect(context.suppressedKeys.isEmpty)
        #expect(try !deliver(.keyDown, key: 14, flags: hyperFlags, repeatKey: true, to: context))
        context.setUserPaused(false)
        #expect(try !deliver(.keyDown, key: 14, flags: hyperFlags, repeatKey: true, to: context))
        #expect(try !deliver(.keyUp, key: 14, flags: [], to: context))
        #expect(actions == ["test.app"])
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        context.setUserPaused(false)
        #expect(try deliver(.keyUp, key: 14, flags: [], to: context))
        #expect(actions == ["test.app", "test.app"])
    }

    @Test func freshDownReconcilesAMissedRelease() throws {
        var actions: [String] = []
        let context = DaemonContext(configuration: configuration, toggleApplication: { actions.append($0) })
        #expect(try deliver(.keyDown, key: 14, flags: hyperFlags, to: context))
        #expect(try !deliver(.keyDown, key: 14, flags: [], to: context))
        #expect(try !deliver(.keyDown, key: 14, flags: hyperFlags, repeatKey: true, to: context))
        #expect(try !deliver(.keyUp, key: 14, flags: hyperFlags, to: context))
        #expect(context.suppressedKeys.isEmpty)
        #expect(actions == ["test.app"])
    }
}

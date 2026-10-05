import CoreGraphics
import Testing
@testable import kvinta

@MainActor
struct DaemonPauseTests {
    private let configuration = Configuration(hyperKey: .rightOption, bindings: [])

    @Test func userPauseDisablesInterceptionUntilResume() {
        let context = DaemonContext(configuration: configuration)
        #expect(context.shouldIntercept)
        context.suppressedKeys.insert(14)
        context.togglePause()
        #expect(context.userPaused)
        #expect(!context.shouldIntercept)
        #expect(context.suppressedKeys.isEmpty)
        context.updateEventTap()
        #expect(!context.shouldIntercept)
        context.togglePause()
        #expect(context.shouldIntercept)
    }

    @Test func reloadPreservesUserPause() {
        let context = DaemonContext(configuration: configuration)
        context.togglePause()
        let updated = Configuration(hyperKey: .leftControl, bindings: [])
        context.reload(configuration: updated)
        #expect(context.configuration == updated)
        #expect(context.userPaused)
        #expect(!context.shouldIntercept)
        context.togglePause()
        #expect(context.shouldIntercept)
    }

    @Test func explicitPauseAndResumeAreIdempotentAndShareMenuState() {
        let context = DaemonContext(configuration: configuration)
        context.setUserPaused(true)
        context.setUserPaused(true)
        context.reload(configuration: configuration)
        #expect(context.userPaused)
        #expect(!context.shouldIntercept)
        context.togglePause()
        #expect(context.shouldIntercept)
        context.togglePause()
        context.setUserPaused(false)
        context.setUserPaused(false)
        #expect(!context.userPaused)
        #expect(context.shouldIntercept)
    }

    @Test func explicitResumePreservesCapturePauseAndItsTimeout() {
        let context = DaemonContext(configuration: configuration)
        context.pauseForCapture()
        let generation = context.pauseGeneration
        context.setUserPaused(true)
        context.setUserPaused(false)
        context.setUserPaused(false)
        #expect(context.capturePaused)
        #expect(!context.shouldIntercept)
        context.finishCapturePause(generation: generation)
        #expect(context.shouldIntercept)
    }

    @Test func captureTimeoutCannotUndoUserPause() {
        let context = DaemonContext(configuration: configuration)
        context.pauseForCapture()
        let generation = context.pauseGeneration
        context.togglePause()
        context.finishCapturePause(generation: generation)
        #expect(!context.capturePaused)
        #expect(context.userPaused)
        #expect(!context.shouldIntercept)
    }

    @Test func finishingCaptureThroughReloadCannotUndoUserPause() {
        let context = DaemonContext(configuration: configuration)
        context.togglePause()
        context.pauseForCapture()
        context.reload(configuration: configuration)
        #expect(!context.capturePaused)
        #expect(context.userPaused)
        #expect(!context.shouldIntercept)
    }

    @Test func oldTimeoutCannotEndNewCapturePause() {
        let context = DaemonContext(configuration: configuration)
        context.pauseForCapture()
        let oldGeneration = context.pauseGeneration
        context.reload(configuration: configuration)
        context.pauseForCapture()
        context.finishCapturePause(generation: oldGeneration)
        #expect(context.capturePaused)
        #expect(!context.shouldIntercept)
        context.finishCapturePause(generation: context.pauseGeneration)
        #expect(context.shouldIntercept)
    }

    @Test func resumeDuringCaptureWaitsForCaptureToFinish() {
        let context = DaemonContext(configuration: configuration)
        context.togglePause()
        context.pauseForCapture()
        context.togglePause()
        #expect(!context.userPaused)
        #expect(!context.shouldIntercept)
        context.finishCapturePause(generation: context.pauseGeneration)
        #expect(context.shouldIntercept)
    }

    @Test func pausedCallbackPassesThroughHyperEventsAndRecoveryNotifications() throws {
        let context = DaemonContext(configuration: configuration)
        context.suppressedKeys.insert(14)
        context.togglePause()
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 14, keyDown: true))
        event.flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        // The callback does not use its proxy. No tap is installed and no
        // events are posted to the live keyboard during this test.
        let proxy = try #require(OpaquePointer(bitPattern: 1))
        for type: CGEventType in [.keyDown, .keyUp, .flagsChanged, .tapDisabledByTimeout, .tapDisabledByUserInput] {
            event.setIntegerValueField(.keyboardEventKeycode, value: type == .flagsChanged ? 61 : 14)
            let result = daemonCallback(proxy: proxy, type: type, event: event, userInfo: pointer)
            #expect(result?.takeUnretainedValue() === event)
            #expect(!context.shouldIntercept)
            #expect(context.suppressedKeys.isEmpty)
        }
    }
}

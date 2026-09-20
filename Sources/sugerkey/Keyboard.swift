import ApplicationServices
import CoreGraphics
import Foundation

enum KeyboardError: LocalizedError {
    case accessibilityRequired
    case eventTapUnavailable
    case captureCancelled

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return "Accessibility permission is required. Enable sugerkey in System Settings > Privacy & Security > Accessibility, then run the command again."
        case .eventTapUnavailable:
            return "Unable to create a keyboard event tap. Check Accessibility and Input Monitoring permissions."
        case .captureCancelled:
            return "Shortcut capture was cancelled."
        }
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

private final class CaptureContext {
    let hyperKey: HyperKey
    var hyperDown = false
    var result: String?
    var runLoop: CFRunLoop?

    init(hyperKey: HyperKey) {
        self.hyperKey = hyperKey
    }
}

private func captureCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<CaptureContext>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .flagsChanged, keyCode == context.hyperKey.keyCode {
        context.hyperDown.toggle()
        return nil
    }

    if type == .keyDown, context.hyperDown {
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           let key = KeyCodes.name(for: keyCode) {
            context.result = key
            if let runLoop = context.runLoop { CFRunLoopStop(runLoop) }
        }
        return nil
    }

    if type == .keyUp, context.hyperDown { return nil }
    return Unmanaged.passUnretained(event)
}

enum ShortcutCapture {
    static func capture(hyperKey: HyperKey) throws -> String {
        guard AccessibilityPermission.request() else { throw KeyboardError.accessibilityRequired }

        let context = CaptureContext(hyperKey: hyperKey)
        let mask = eventMask([.flagsChanged, .keyDown, .keyUp])
        let pointer = Unmanaged.passUnretained(context).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: captureCallback,
            userInfo: pointer
        ) else {
            throw KeyboardError.eventTapUnavailable
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw KeyboardError.eventTapUnavailable
        }
        context.runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(context.runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
        CFRunLoopRemoveSource(context.runLoop, source, .commonModes)

        guard let result = context.result else { throw KeyboardError.captureCancelled }
        return result
    }
}

func eventMask(_ types: [CGEventType]) -> CGEventMask {
    types.reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }
}

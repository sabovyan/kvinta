import CoreGraphics
import Testing
@testable import kvinta

struct HyperKeyTests {
    // Hardware modifier flag snapshots, including both sides of each family.
    private let pairs: [(HyperKey, HyperKey, UInt64, UInt64, CGEventFlags)] = [
        (.leftOption, .rightOption, 0x20, 0x40, .maskAlternate),
        (.leftControl, .rightControl, 0x01, 0x2000, .maskControl),
        (.leftCommand, .rightCommand, 0x08, 0x10, .maskCommand),
    ]

    @Test func releasingConfiguredSideWhileOppositeSideIsHeld() {
        for (left, right, leftMask, rightMask, aggregate) in pairs {
            for (configured, ownMask, otherMask) in [(left, leftMask, rightMask), (right, rightMask, leftMask)] {
                let sequence: [(UInt64, Bool)] = [
                    (0, false),
                    (aggregate.rawValue | ownMask, true),
                    (aggregate.rawValue | ownMask | otherMask, true),
                    (aggregate.rawValue | otherMask, false),
                    (0, false),
                ]
                for (rawFlags, expected) in sequence {
                    #expect(configured.isPressed(in: CGEventFlags(rawValue: rawFlags)) == expected)
                }
            }
        }
    }

    @Test func releasingOppositeSideFirstKeepsHyperPressed() {
        for (left, right, leftMask, rightMask, aggregate) in pairs {
            for (configured, ownMask, otherMask) in [(left, leftMask, rightMask), (right, rightMask, leftMask)] {
                let sequence: [(UInt64, Bool)] = [
                    (aggregate.rawValue | otherMask, false),
                    (aggregate.rawValue | ownMask | otherMask, true),
                    (aggregate.rawValue | ownMask, true),
                    (0, false),
                ]
                for (rawFlags, expected) in sequence {
                    #expect(configured.isPressed(in: CGEventFlags(rawValue: rawFlags)) == expected)
                }
            }
        }
    }

    @Test func missingAndDuplicateTransitionsCannotRetainPressedState() {
        for (left, right, leftMask, rightMask, aggregate) in pairs {
            for (configured, ownMask, otherMask) in [(left, leftMask, rightMask), (right, rightMask, leftMask)] {
                // First observed event may be a key-down after startup/reload,
                // with Hyper already held. No preceding flagsChanged is needed.
                let held = CGEventFlags(rawValue: aggregate.rawValue | ownMask)
                #expect(configured.isPressed(in: held))
                #expect(configured.isPressed(in: held))
                // A later key event recovers even if Hyper release was missed.
                #expect(!configured.isPressed(in: []))
                #expect(!configured.isPressed(in: CGEventFlags(rawValue: aggregate.rawValue | otherMask)))
                #expect(configured.isPressed(in: held))
            }
        }
    }

    @Test func ambiguousOrInconsistentFlagsFailOpen() {
        for (left, right, leftMask, rightMask, aggregate) in pairs {
            for (configured, ownMask) in [(left, leftMask), (right, rightMask)] {
                #expect(!configured.isPressed(in: aggregate))
                #expect(!configured.isPressed(in: CGEventFlags(rawValue: ownMask)))
                let unrelated = CGEventFlags.maskShift.union(.maskSecondaryFn)
                #expect(!configured.isPressed(in: unrelated))
                #expect(configured.isPressed(in: CGEventFlags(rawValue: aggregate.rawValue | ownMask).union(unrelated)))
            }
        }
    }
}

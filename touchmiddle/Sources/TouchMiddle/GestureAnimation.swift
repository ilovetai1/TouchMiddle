import Foundation
import TouchMiddleCore

/// Presentation-only contacts in normalized, top-down trackpad coordinates.
/// This model never receives touch input or sends gesture actions.
struct GestureAnimation {
    static let duration: TimeInterval = 3.2

    struct Dot {
        let position: CGPoint
        let opacity: Double
    }

    struct Ripple {
        let position: CGPoint
        let progress: Double
    }

    struct Frame {
        var dots: [Dot] = []
        var ripples: [Ripple] = []
    }

    private struct Contact {
        let origin: CGPoint
        var destination: CGPoint? = nil
        let start: TimeInterval
        let end: TimeInterval
        var fades = false
        var ripples = true
    }

    private let contacts: [Contact]

    /// Pick a contact phase, including the second tap of double-tap gestures.
    var stillFrame: Frame {
        frame(at: contacts.reduce(0) { max($0, $1.start) } + 0.09)
    }

    init(gesture: GestureKind) {
        switch gesture {
        case .threeFingerTap:
            contacts = Self.taps(xs: [0.34, 0.50, 0.66])
        case .twoFingerDoubleTap:
            contacts = Self.taps(xs: [0.42, 0.58], starts: [0.85, 1.25])
        case .threeFingerDoubleTap:
            contacts = Self.taps(xs: [0.34, 0.50, 0.66], starts: [0.85, 1.25])
        case .fourFingerTap:
            contacts = Self.taps(xs: [0.26, 0.42, 0.58, 0.74])
        case .threeFingerLongPress:
            contacts = [0.34, 0.50, 0.66].map {
                Contact(origin: CGPoint(x: $0, y: 0.50), start: 0.65, end: 1.65)
            }
        case .oneFingerHoldLeftTap:
            contacts = Self.anchored(count: 1, right: false)
        case .oneFingerHoldRightTap:
            contacts = Self.anchored(count: 1, right: true)
        case .twoFingerHoldLeftTap:
            contacts = Self.anchored(count: 2, right: false)
        case .twoFingerHoldRightTap:
            contacts = Self.anchored(count: 2, right: true)
        case .twoFingerHoldLeftDoubleTap:
            contacts = Self.anchored(count: 2, right: false, doubleTap: true)
        case .twoFingerHoldRightDoubleTap:
            contacts = Self.anchored(count: 2, right: true, doubleTap: true)
        case .twoFingerHoldSwipeUp:
            contacts = Self.swipe(up: true)
        case .twoFingerHoldSwipeDown:
            contacts = Self.swipe(up: false)
        case .topLeftTwoFingerTap:
            contacts = Self.taps(xs: [0.10, 0.20], y: 0.15)
        case .topRightTwoFingerTap:
            contacts = Self.taps(xs: [0.80, 0.90], y: 0.15)
        case .bottomLeftTwoFingerTap:
            contacts = Self.taps(xs: [0.10, 0.20], y: 0.85)
        case .bottomRightTwoFingerTap:
            contacts = Self.taps(xs: [0.80, 0.90], y: 0.85)
        }
    }

    func frame(at elapsed: TimeInterval) -> Frame {
        let time = max(0, elapsed).truncatingRemainder(dividingBy: Self.duration)
        var frame = Frame()
        for contact in contacts {
            if time >= contact.start && time < contact.end {
                let progress = Self.ease((time - contact.start) / (contact.end - contact.start))
                let destination = contact.destination ?? contact.origin
                let position = CGPoint(
                    x: contact.origin.x + (destination.x - contact.origin.x) * progress,
                    y: contact.origin.y + (destination.y - contact.origin.y) * progress
                )
                let opacity = contact.fades
                    ? min(Self.ease((time - contact.start) / 0.24), Self.ease((contact.end - time) / 0.28))
                    : 1
                frame.dots.append(Dot(position: position, opacity: opacity))
            }
            // Swipes pulse at release, so the pulse follows the moving contact.
            let pulseTime = contact.destination == nil ? contact.start : contact.end
            let pulseProgress = (time - pulseTime) / 0.64
            if contact.ripples && pulseProgress >= 0 && pulseProgress < 1 {
                frame.ripples.append(Ripple(
                    position: contact.destination ?? contact.origin, progress: pulseProgress
                ))
            }
        }
        return frame
    }

    private static func taps(
        xs: [Double], y: Double = 0.50, starts: [TimeInterval] = [1.1]
    ) -> [Contact] {
        starts.flatMap { start in
            xs.map { Contact(origin: CGPoint(x: $0, y: y), start: start, end: start + 0.18) }
        }
    }

    private static func anchors(xs: [Double]) -> [Contact] {
        xs.map {
            Contact(origin: CGPoint(x: $0, y: 0.50), start: 0, end: 2.88, fades: true, ripples: false)
        }
    }

    private static func anchored(count: Int, right: Bool, doubleTap: Bool = false) -> [Contact] {
        let xs = count == 1 ? [0.55] : [0.53, 0.69]
        let held = anchors(xs: xs.map { right ? 1 - $0 : $0 })
        return held + taps(xs: [right ? 0.74 : 0.26], starts: doubleTap ? [1.1, 1.50] : [1.1])
    }

    private static func swipe(up: Bool) -> [Contact] {
        anchors(xs: [0.40, 0.57]) + [
            Contact(
                origin: CGPoint(x: 0.77, y: up ? 0.65 : 0.35),
                destination: CGPoint(x: 0.77, y: up ? 0.35 : 0.65),
                start: 1.1, end: 1.34
            )
        ]
    }

    private static func ease(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value * value * (3 - 2 * value)
    }
}

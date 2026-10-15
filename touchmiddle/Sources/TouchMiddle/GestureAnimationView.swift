import SwiftUI
import TouchMiddleCore

struct GestureAnimationView: View {
    let gesture: GestureKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var startedAt = Date()
    @State private var isVisible = false

    var body: some View {
        let animation = GestureAnimation(gesture: gesture)
        let showsStillFrame = reduceMotion || activeState == .inactive
        TimelineView(.animation(
            minimumInterval: 1.0 / 30,
            paused: showsStillFrame || !isVisible
        )) { timeline in
            GestureAnimationDrawing(frame: showsStillFrame ? animation.stillFrame : animation.frame(
                at: timeline.date.timeIntervalSince(startedAt)
            ))
        }
        .frame(width: 244, height: 148)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gesture.title)。\(gesture.instructions)")
        .onAppear {
            startedAt = Date()
            isVisible = true
        }
        .onDisappear { isVisible = false }
        .onChange(of: gesture) { _, _ in startedAt = Date() }
        .onChange(of: activeState) { _, state in
            if state != .inactive { startedAt = Date() }
        }
    }
}

struct GestureAnimationDrawing: View {
    let frame: GestureAnimation.Frame
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let pad = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let outline = Path(roundedRect: pad, cornerRadius: pad.width * 0.06)
            let background = colorScheme == .dark
                ? Color(red: 0.145, green: 0.153, blue: 0.176)
                : Color(red: 0.961, green: 0.965, blue: 0.973)
            context.fill(outline, with: .color(background))
            context.stroke(outline, with: .color(.primary.opacity(0.16)), lineWidth: 1)

            // Clip expanding corner pulses to the trackpad surface.
            context.clip(to: outline)
            let scale = pad.width / 436
            for ripple in frame.ripples {
                let radius = (15 + 24 * ripple.progress) * scale
                let center = point(ripple.position, in: pad)
                let circle = Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
                ))
                context.stroke(circle, with: .color(.blue.opacity((1 - ripple.progress) * 0.85)), lineWidth: 1)
            }
            for dot in frame.dots {
                let radius = 13 * scale
                let center = point(dot.position, in: pad)
                let circle = Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
                ))
                context.fill(circle, with: .color(.blue.opacity(dot.opacity)))
            }
        }
    }

    private func point(_ position: CGPoint, in pad: CGRect) -> CGPoint {
        CGPoint(x: pad.minX + position.x * pad.width, y: pad.minY + position.y * pad.height)
    }
}

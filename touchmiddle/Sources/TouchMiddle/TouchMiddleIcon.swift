import AppKit
import CoreGraphics

/// B1-S1: three rounded fingertips leaning in the direction of a swipe.
/// The app icon and menu bar share this geometry so they stay consistent.
enum TouchMiddleIcon {
    @MainActor
    static let menuBarImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                preconditionFailure("TouchMiddle icon requires a graphics context")
            }
            drawMenuBarSymbol(in: rect, context: context)
            return true
        }
        image.isTemplate = true
        return image
    }()

    static func drawMenuBarSymbol(in rect: CGRect, context: CGContext) {
        let path = silhouette()
        let bounds = path.boundingBoxOfPath
        let side = max(bounds.width, bounds.height)
        let viewBox = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2,
                             width: side, height: side)
        let inset = rect.width / 18
        draw(path, viewBox: viewBox, in: rect.insetBy(dx: inset, dy: inset),
             color: CGColor(gray: 0, alpha: 1), context: context)
    }

    static func drawAppIcon(in rect: CGRect, context: CGContext) {
        let tile = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        let radius = tile.width * 35 / 154
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius,
                               transform: nil))
        context.fillPath()
        let padding = tile.width * 11 / 154
        draw(silhouette(), viewBox: CGRect(x: 0, y: 0, width: 128, height: 128),
             in: tile.insetBy(dx: padding, dy: padding), color: CGColor(gray: 1, alpha: 1),
             context: context)
    }

    private static func draw(_ path: CGPath, viewBox: CGRect, in rect: CGRect,
                             color: CGColor, context: CGContext) {
        context.saveGState()
        context.setShouldAntialias(true)
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / viewBox.width, y: -rect.height / viewBox.height)
        context.translateBy(x: -viewBox.minX, y: -viewBox.minY)
        context.setFillColor(color)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    private static func silhouette() -> CGPath {
        let path = CGMutablePath()
        addRibbon(to: path, points: [(39, 76), (39, 64), (42, 52), (46, 42)],
                  startWidth: 8, endWidth: 12)
        addRibbon(to: path, points: [(62, 82), (63, 65), (67, 47), (71, 30)],
                  startWidth: 8, endWidth: 12)
        addRibbon(to: path, points: [(85, 76), (86, 64), (90, 54), (94, 44)],
                  startWidth: 8, endWidth: 12)
        addRibbon(to: path, points: [(35, 93), (54, 109), (73, 109), (92, 92)],
                  startWidth: 6, endWidth: 6)
        return path
    }

    /// A tapered cubic ribbon with round caps; coordinates use SVG's downward Y axis.
    private static func addRibbon(to path: CGMutablePath, points: [(CGFloat, CGFloat)],
                                  startWidth: CGFloat, endWidth: CGFloat) {
        let control = points.map { CGPoint(x: $0.0, y: $0.1) }
        func position(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(
                x: u*u*u*control[0].x + 3*u*u*t*control[1].x + 3*u*t*t*control[2].x + t*t*t*control[3].x,
                y: u*u*u*control[0].y + 3*u*u*t*control[1].y + 3*u*t*t*control[2].y + t*t*t*control[3].y)
        }
        func tangent(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(
                x: 3*u*u*(control[1].x-control[0].x) + 6*u*t*(control[2].x-control[1].x) + 3*t*t*(control[3].x-control[2].x),
                y: 3*u*u*(control[1].y-control[0].y) + 6*u*t*(control[2].y-control[1].y) + 3*t*t*(control[3].y-control[2].y))
        }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for step in 0...80 {
            let t = CGFloat(step) / 80
            let point = position(t)
            let direction = tangent(t)
            let length = hypot(direction.x, direction.y)
            let radius = (startWidth * (1 - t) + endWidth * t) / 2
            let offset = CGPoint(x: -direction.y / length * radius,
                                 y: direction.x / length * radius)
            left.append(CGPoint(x: point.x + offset.x, y: point.y + offset.y))
            right.append(CGPoint(x: point.x - offset.x, y: point.y - offset.y))
        }
        func cap(at t: CGFloat, radius: CGFloat, angle: CGFloat) -> [CGPoint] {
            let center = position(t)
            return (0...32).map { step in
                let a = angle - .pi * CGFloat(step) / 32
                return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            }
        }
        let end = tangent(1)
        let start = tangent(0)
        let outline = left
            + cap(at: 1, radius: endWidth / 2, angle: atan2(end.y, end.x) + .pi / 2)
            + right.reversed()
            + cap(at: 0, radius: startWidth / 2, angle: atan2(start.y, start.x) - .pi / 2)
        path.move(to: outline[0])
        for point in outline.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
    }
}

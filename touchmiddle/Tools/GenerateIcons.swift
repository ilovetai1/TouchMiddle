import AppKit
import CoreGraphics
import Foundation

/// Builds icon files with AppKit only; no downloaded assets or image libraries.
@main
enum GenerateIcons {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else {
            throw failure("Usage: generate-icons /absolute/new/output-directory")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw failure("Refusing existing icon output: \(output.path)")
        }
        let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 1 ? "" : "@2x"
                let destination = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
                try render(pixels: size * scale, to: destination, draw: TouchMiddleIcon.drawAppIcon)
            }
        }
        try render(pixels: 1024, to: output.appendingPathComponent("AppIcon-1024.png"),
                   draw: TouchMiddleIcon.drawAppIcon)
        for scale in [1, 2] {
            let suffix = scale == 1 ? "" : "@2x"
            try render(pixels: 18 * scale,
                       to: output.appendingPathComponent("MenuBarTemplate\(suffix).png"),
                       draw: TouchMiddleIcon.drawMenuBarSymbol)
        }
        guard TouchMiddleIcon.menuBarImage.isTemplate,
              TouchMiddleIcon.menuBarImage.size == NSSize(width: 18, height: 18) else {
            throw failure("Menu bar icon must be an 18-point template image")
        }
        print("Generated ten app icon representations and 18-point menu bar templates: \(output.path)")
    }

    private static func render(pixels: Int, to destination: URL,
                               draw: (CGRect, CGContext) -> Void) throws {
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw failure("Cannot create \(pixels)-pixel icon context")
        }
        draw(CGRect(x: 0, y: 0, width: pixels, height: pixels), context)
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw failure("Cannot encode icon: \(destination.lastPathComponent)")
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TouchMiddle.GenerateIcons", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}

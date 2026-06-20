import AppKit
import Foundation

struct IconSlot {
    let size: Int
    let scales: [Int]
}

let appIconRoot = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "BatteryHub/Mac/Assets.xcassets/AppIcon.appiconset"
)
let assetCatalogRoot = appIconRoot.deletingLastPathComponent()
try FileManager.default.createDirectory(at: appIconRoot, withIntermediateDirectories: true)

let slots = [16, 32, 128, 256, 512].map { IconSlot(size: $0, scales: [1, 2]) }

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func bitmap(pixelSize: Int, draw: (CGFloat, CGRect) -> Void) throws -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "BatteryHubIcon", code: 1)
    }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let side = CGFloat(pixelSize)
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    draw(side, rect)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BatteryHubIcon", code: 2)
    }
    return data
}

func drawAppIcon(side: CGFloat, rect: CGRect) {
    let plate = rect.insetBy(dx: side * 0.07, dy: side * 0.07)

    NSColor(calibratedRed: 0.135, green: 0.142, blue: 0.148, alpha: 1).setFill()
    roundedRect(plate, radius: side * 0.215).fill()

    NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
    let outerStroke = roundedRect(plate.insetBy(dx: side * 0.01, dy: side * 0.01), radius: side * 0.205)
    outerStroke.lineWidth = max(1, side * 0.014)
    outerStroke.stroke()

    let grid = rect.insetBy(dx: side * 0.245, dy: side * 0.225)
    NSColor(calibratedRed: 0.77, green: 0.82, blue: 0.78, alpha: 1).setStroke()
    let gridOutline = roundedRect(grid, radius: side * 0.075)
    gridOutline.lineWidth = max(1.25, side * 0.035)
    gridOutline.stroke()

    NSColor(calibratedRed: 0.77, green: 0.82, blue: 0.78, alpha: 1).setFill()
    let divider = max(1, side * 0.026)
    let inset = side * 0.06
    roundedRect(
        CGRect(
            x: grid.midX - divider / 2,
            y: grid.minY + inset,
            width: divider,
            height: grid.height - inset * 2
        ),
        radius: divider / 2
    ).fill()
    roundedRect(
        CGRect(
            x: grid.minX + inset,
            y: grid.midY - divider / 2,
            width: grid.width - inset * 2,
            height: divider
        ),
        radius: divider / 2
    ).fill()
}

func drawTemplateGlyph(side: CGFloat, rect: CGRect) {
    let grid = rect.insetBy(dx: side * 0.18, dy: side * 0.18)

    NSColor.white.setStroke()
    let gridOutline = roundedRect(grid, radius: side * 0.105)
    gridOutline.lineWidth = max(1.4, side * 0.085)
    gridOutline.stroke()

    NSColor.white.setFill()
    let divider = max(1, side * 0.072)
    let inset = side * 0.125
    roundedRect(
        CGRect(
            x: grid.midX - divider / 2,
            y: grid.minY + inset,
            width: divider,
            height: grid.height - inset * 2
        ),
        radius: divider / 2
    ).fill()
    roundedRect(
        CGRect(
            x: grid.minX + inset,
            y: grid.midY - divider / 2,
            width: grid.width - inset * 2,
            height: divider
        ),
        radius: divider / 2
    ).fill()
}

func renderAppIconPNG(pixelSize: Int) throws -> Data {
    try bitmap(pixelSize: pixelSize, draw: drawAppIcon)
}

func renderTemplateGlyphPNG(pixelSize: Int) throws -> Data {
    try bitmap(pixelSize: pixelSize, draw: drawTemplateGlyph)
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: url)
}

var images: [[String: String]] = []
for slot in slots {
    for scale in slot.scales {
        let filename = "icon_\(slot.size)x\(slot.size)@\(scale)x.png"
        try renderAppIconPNG(pixelSize: slot.size * scale)
            .write(to: appIconRoot.appendingPathComponent(filename))
        images.append([
            "idiom": "mac",
            "size": "\(slot.size)x\(slot.size)",
            "scale": "\(scale)x",
            "filename": filename
        ])
    }
}

try writeJSON([
    "images": images,
    "info": [
        "author": "xcode",
        "version": 1
    ]
], to: appIconRoot.appendingPathComponent("Contents.json"))

func writeImageSet(
    name: String,
    basePixelSize: Int,
    renderer: (Int) throws -> Data,
    templateRendering: Bool = false
) throws {
    let output = assetCatalogRoot.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    var images: [[String: String]] = []
    for scale in [1, 2, 3] {
        let filename = "\(name)@\(scale)x.png"
        try renderer(basePixelSize * scale)
            .write(to: output.appendingPathComponent(filename))
        images.append([
            "idiom": "universal",
            "scale": "\(scale)x",
            "filename": filename
        ])
    }

    var contents: [String: Any] = [
        "images": images,
        "info": [
            "author": "xcode",
            "version": 1
        ]
    ]
    if templateRendering {
        contents["properties"] = [
            "template-rendering-intent": "template"
        ]
    }
    try writeJSON(contents, to: output.appendingPathComponent("Contents.json"))
}

try writeImageSet(
    name: "BatteryHubAppIcon",
    basePixelSize: 32,
    renderer: renderAppIconPNG
)
try writeImageSet(
    name: "BatteryHubStatusGlyph",
    basePixelSize: 18,
    renderer: renderTemplateGlyphPNG,
    templateRendering: true
)

print(appIconRoot.path)

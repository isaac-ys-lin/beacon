import AppKit
import Foundation

struct IconSlot {
    let size: Int
    let scales: [Int]
}

let appIconRoot = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "Beacon/Mac/Assets.xcassets/AppIcon.appiconset"
)
let assetCatalogRoot = appIconRoot.deletingLastPathComponent()
try FileManager.default.createDirectory(at: appIconRoot, withIntermediateDirectories: true)

let slots = [16, 32, 128, 256, 512].map { IconSlot(size: $0, scales: [1, 2]) }

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    roundedRect(rect, radius: radius).fill()
}

func strokeRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat) {
    color.setStroke()
    let path = roundedRect(rect, radius: radius)
    path.lineWidth = lineWidth
    path.stroke()
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
        throw NSError(domain: "BeaconIcon", code: 1)
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
        throw NSError(domain: "BeaconIcon", code: 2)
    }
    return data
}

func drawAppIcon(side: CGFloat, rect: CGRect) {
    drawBeaconWatcherAppIcon(side: side, rect: rect)
}

func fillOval(_ rect: CGRect, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

func strokeArc(
    center: CGPoint,
    radius: CGFloat,
    startAngle: CGFloat,
    endAngle: CGFloat,
    color: NSColor,
    lineWidth: CGFloat
) {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    color.setStroke()
    arc.stroke()
}

func drawBeaconRays(center: CGPoint, side: CGFloat, color: NSColor, compact: Bool) {
    let innerRadius = side * (compact ? 0.14 : 0.15)
    let outerRadius = side * (compact ? 0.235 : 0.235)
    let strokeWidth = max(compact ? 1.2 : 2.0, side * (compact ? 0.052 : 0.033))

    strokeArc(
        center: center,
        radius: innerRadius,
        startAngle: 18,
        endAngle: 76,
        color: color.withAlphaComponent(compact ? 0.94 : 0.98),
        lineWidth: strokeWidth
    )
    strokeArc(
        center: center,
        radius: outerRadius,
        startAngle: 16,
        endAngle: 80,
        color: color.withAlphaComponent(compact ? 0.78 : 0.86),
        lineWidth: max(compact ? 1.0 : 1.6, strokeWidth * 0.78)
    )
}

func drawBeaconMark(
    center: CGPoint,
    side: CGFloat,
    foreground: NSColor,
    compact: Bool
) {
    let stemWidth = max(compact ? 1.6 : 3.0, side * (compact ? 0.075 : 0.065))
    let stemHeight = side * (compact ? 0.25 : 0.255)
    let stem = CGRect(
        x: center.x - stemWidth / 2,
        y: center.y - stemHeight - side * 0.045,
        width: stemWidth,
        height: stemHeight
    )

    foreground.withAlphaComponent(compact ? 0.94 : 0.98).setFill()
    roundedRect(stem, radius: stemWidth / 2).fill()

    fillOval(
        CGRect(
            x: center.x - side * (compact ? 0.072 : 0.045),
            y: center.y - side * (compact ? 0.072 : 0.045),
            width: side * (compact ? 0.144 : 0.09),
            height: side * (compact ? 0.144 : 0.09)
        ),
        color: foreground
    )

    drawBeaconRays(center: center, side: side, color: foreground, compact: compact)
}

func drawBeaconWatcherAppIcon(side: CGFloat, rect: CGRect) {
    let compact = side <= 64
    let plate = rect.insetBy(dx: side * 0.041, dy: side * 0.041)
    let platePath = roundedRect(plate, radius: side * 0.215)
    let plateGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.024, green: 0.043, blue: 0.078, alpha: 1),
        NSColor(calibratedRed: 0.035, green: 0.073, blue: 0.125, alpha: 1),
        NSColor(calibratedRed: 0.056, green: 0.102, blue: 0.165, alpha: 1)
    ])
    plateGradient?.draw(in: platePath, angle: -90)

    if !compact {
        fillOval(
            CGRect(
                x: side * 0.24,
                y: side * 0.29,
                width: side * 0.58,
                height: side * 0.58
            ),
            color: NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.96, alpha: 0.11)
        )
        fillOval(
            CGRect(
                x: side * 0.39,
                y: side * 0.46,
                width: side * 0.31,
                height: side * 0.31
            ),
            color: NSColor(calibratedRed: 0.63, green: 0.91, blue: 1, alpha: 0.16)
        )
    }

    strokeRoundedRect(
        plate.insetBy(dx: side * 0.006, dy: side * 0.006),
        radius: side * 0.208,
        color: NSColor(calibratedWhite: 1, alpha: compact ? 0.12 : 0.16),
        lineWidth: max(1, side * 0.004)
    )

    let markCenter = CGPoint(x: side * 0.49, y: side * (compact ? 0.58 : 0.575))
    if !compact {
        fillOval(
            CGRect(
                x: markCenter.x - side * 0.12,
                y: markCenter.y - side * 0.12,
                width: side * 0.24,
                height: side * 0.24
            ),
            color: NSColor(calibratedRed: 0.51, green: 0.87, blue: 1, alpha: 0.18)
        )
    }
    drawBeaconMark(
        center: markCenter,
        side: side,
        foreground: NSColor(calibratedRed: 0.91, green: 0.98, blue: 1, alpha: 1),
        compact: compact
    )

    if !compact {
        let footWidth = side * 0.16
        let footHeight = side * 0.026
        fillRoundedRect(
            CGRect(
                x: markCenter.x - footWidth / 2,
                y: markCenter.y - side * 0.33,
                width: footWidth,
                height: footHeight
            ),
            radius: footHeight / 2,
            color: NSColor(calibratedRed: 0.55, green: 0.86, blue: 0.98, alpha: 0.36)
        )
    }
}

func drawInventoryHubIcon(side: CGFloat, rect: CGRect) {
    let plate = rect.insetBy(dx: side * 0.07, dy: side * 0.07)

    let platePath = roundedRect(plate, radius: side * 0.215)
    let plateGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.085, green: 0.105, blue: 0.128, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.145, blue: 0.16, alpha: 1)
    ])
    plateGradient?.draw(in: platePath, angle: -90)

    strokeRoundedRect(
        plate.insetBy(dx: side * 0.01, dy: side * 0.01),
        radius: side * 0.205,
        color: NSColor(calibratedWhite: 1, alpha: 0.1),
        lineWidth: max(1, side * 0.012)
    )

    let tray = plate.insetBy(dx: side * 0.125, dy: side * 0.13)
    let trayPath = roundedRect(tray, radius: side * 0.075)
    let trayGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.205, blue: 0.23, alpha: 0.96),
        NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.15, alpha: 0.96)
    ])
    trayGradient?.draw(in: trayPath, angle: -90)
    strokeRoundedRect(
        tray,
        radius: side * 0.075,
        color: NSColor(calibratedWhite: 1, alpha: 0.09),
        lineWidth: max(1, side * 0.008)
    )

    let gap = side * 0.036
    let cellWidth = (tray.width - gap * 3) / 2
    let cellHeight = (tray.height - gap * 3) / 2
    let cells = [
        CGRect(x: tray.minX + gap, y: tray.midY + gap / 2, width: cellWidth, height: cellHeight),
        CGRect(x: tray.midX + gap / 2, y: tray.midY + gap / 2, width: cellWidth, height: cellHeight),
        CGRect(x: tray.minX + gap, y: tray.minY + gap, width: cellWidth, height: cellHeight),
        CGRect(x: tray.midX + gap / 2, y: tray.minY + gap, width: cellWidth, height: cellHeight)
    ]
    let accents = [
        NSColor(calibratedRed: 0.34, green: 0.75, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.47, green: 0.88, blue: 0.58, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.31, alpha: 1),
        NSColor(calibratedRed: 0.71, green: 0.58, blue: 0.96, alpha: 1)
    ]

    for (index, cell) in cells.enumerated() {
        drawInventoryCell(index: index, cell: cell, accent: accents[index], side: side)
    }

    drawHubCore(center: CGPoint(x: tray.midX, y: tray.midY), side: side)
}

func drawInventoryCell(index: Int, cell: CGRect, accent: NSColor, side: CGFloat) {
    let radius = side * 0.034
    fillRoundedRect(
        cell,
        radius: radius,
        color: NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.13, alpha: 1)
    )
    strokeRoundedRect(
        cell.insetBy(dx: side * 0.003, dy: side * 0.003),
        radius: radius,
        color: accent.withAlphaComponent(0.42),
        lineWidth: max(1, side * 0.006)
    )

    let glyphRect = cell.insetBy(dx: side * 0.035, dy: side * 0.042)
    let glyphColor = NSColor(calibratedRed: 0.86, green: 0.92, blue: 0.9, alpha: 1)
    switch index {
    case 0:
        drawWideDevice(in: glyphRect, color: glyphColor, side: side)
    case 1:
        drawCapsuleDevices(in: glyphRect, color: glyphColor, side: side)
    case 2:
        drawInputDevice(in: glyphRect, color: glyphColor, side: side)
    default:
        drawTallDevice(in: glyphRect, color: glyphColor, side: side)
    }

    let barHeight = max(2, side * 0.025)
    let barWidth = cell.width * [0.68, 0.46, 0.82, 0.56][index]
    let bar = CGRect(
        x: cell.minX + side * 0.035,
        y: cell.minY + side * 0.035,
        width: barWidth,
        height: barHeight
    )
    fillRoundedRect(bar, radius: barHeight / 2, color: accent)

    let capWidth = max(1, barHeight * 0.38)
    fillRoundedRect(
        CGRect(x: bar.maxX + capWidth * 0.35, y: bar.minY + barHeight * 0.25, width: capWidth, height: barHeight * 0.5),
        radius: capWidth / 2,
        color: accent.withAlphaComponent(0.8)
    )
}

func drawWideDevice(in rect: CGRect, color: NSColor, side: CGFloat) {
    strokeRoundedRect(
        CGRect(x: rect.minX, y: rect.midY - rect.height * 0.18, width: rect.width, height: rect.height * 0.42),
        radius: side * 0.015,
        color: color,
        lineWidth: max(1.4, side * 0.01)
    )
    fillRoundedRect(
        CGRect(x: rect.midX - rect.width * 0.16, y: rect.minY + rect.height * 0.16, width: rect.width * 0.32, height: max(1, side * 0.012)),
        radius: side * 0.006,
        color: color.withAlphaComponent(0.85)
    )
}

func drawCapsuleDevices(in rect: CGRect, color: NSColor, side: CGFloat) {
    let podWidth = rect.width * 0.22
    let podHeight = rect.height * 0.55
    fillRoundedRect(
        CGRect(x: rect.midX - podWidth * 1.25, y: rect.midY - podHeight / 2, width: podWidth, height: podHeight),
        radius: podWidth / 2,
        color: color
    )
    fillRoundedRect(
        CGRect(x: rect.midX + podWidth * 0.25, y: rect.midY - podHeight / 2, width: podWidth, height: podHeight),
        radius: podWidth / 2,
        color: color
    )
    fillRoundedRect(
        CGRect(x: rect.midX - rect.width * 0.22, y: rect.minY + rect.height * 0.16, width: rect.width * 0.44, height: max(1, side * 0.011)),
        radius: side * 0.006,
        color: color.withAlphaComponent(0.76)
    )
}

func drawInputDevice(in rect: CGRect, color: NSColor, side: CGFloat) {
    fillRoundedRect(
        CGRect(x: rect.minX, y: rect.midY - rect.height * 0.11, width: rect.width * 0.72, height: rect.height * 0.24),
        radius: side * 0.012,
        color: color
    )
    fillRoundedRect(
        CGRect(x: rect.maxX - rect.width * 0.22, y: rect.midY - rect.height * 0.17, width: rect.width * 0.22, height: rect.height * 0.34),
        radius: rect.width * 0.11,
        color: color.withAlphaComponent(0.82)
    )
}

func drawTallDevice(in rect: CGRect, color: NSColor, side: CGFloat) {
    strokeRoundedRect(
        CGRect(x: rect.midX - rect.width * 0.21, y: rect.minY + rect.height * 0.08, width: rect.width * 0.42, height: rect.height * 0.68),
        radius: side * 0.018,
        color: color,
        lineWidth: max(1.4, side * 0.01)
    )
    fillRoundedRect(
        CGRect(x: rect.midX - rect.width * 0.085, y: rect.minY + rect.height * 0.15, width: rect.width * 0.17, height: max(1, side * 0.009)),
        radius: side * 0.005,
        color: color.withAlphaComponent(0.78)
    )
}

func drawHubCore(center: CGPoint, side: CGFloat) {
    let coreSide = side * 0.145
    let core = CGRect(x: center.x - coreSide / 2, y: center.y - coreSide / 2, width: coreSide, height: coreSide)
    fillRoundedRect(
        core,
        radius: coreSide * 0.28,
        color: NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.085, alpha: 1)
    )
    strokeRoundedRect(
        core.insetBy(dx: side * 0.006, dy: side * 0.006),
        radius: coreSide * 0.24,
        color: NSColor(calibratedWhite: 1, alpha: 0.18),
        lineWidth: max(1, side * 0.007)
    )

    let pipHeight = max(2, side * 0.015)
    let pipWidth = coreSide * 0.58
    let pipGap = pipHeight * 0.75
    let startY = center.y - pipHeight * 1.5 - pipGap
    let colors = [
        NSColor(calibratedRed: 0.34, green: 0.75, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.47, green: 0.88, blue: 0.58, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.31, alpha: 1)
    ]
    for index in 0..<3 {
        fillRoundedRect(
            CGRect(
                x: center.x - pipWidth / 2,
                y: startY + CGFloat(index) * (pipHeight + pipGap),
                width: pipWidth * [0.72, 1.0, 0.58][index],
                height: pipHeight
            ),
            radius: pipHeight / 2,
            color: colors[index]
        )
    }
}

func drawSmallInventoryHubIcon(side: CGFloat, rect: CGRect) {
    let plateInset = max(1, round(side * 0.07))
    let plate = rect.insetBy(dx: plateInset, dy: plateInset)

    fillRoundedRect(
        plate,
        radius: max(3, side * 0.2),
        color: NSColor(calibratedRed: 0.09, green: 0.105, blue: 0.12, alpha: 1)
    )

    strokeRoundedRect(
        plate.insetBy(dx: 0.5, dy: 0.5),
        radius: max(2.5, side * 0.19),
        color: NSColor(calibratedWhite: 1, alpha: 0.08),
        lineWidth: 1
    )

    let gap = max(1, round(side * 0.08))
    let grid = plate.insetBy(dx: max(2, round(side * 0.18)), dy: max(2, round(side * 0.18)))
    let tile = floor((min(grid.width, grid.height) - gap) / 2)
    let originX = round((side - tile * 2 - gap) / 2)
    let originY = round((side - tile * 2 - gap) / 2)
    let tileRadius = max(1, round(side * 0.045))
    let colors = [
        NSColor(calibratedRed: 0.34, green: 0.75, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.47, green: 0.88, blue: 0.58, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.31, alpha: 1),
        NSColor(calibratedRed: 0.71, green: 0.58, blue: 0.96, alpha: 1)
    ]

    for index in 0..<4 {
        let col = CGFloat(index % 2)
        let row = CGFloat(index / 2)
        let cell = CGRect(
            x: originX + col * (tile + gap),
            y: originY + row * (tile + gap),
            width: tile,
            height: tile
        )
        fillRoundedRect(cell, radius: tileRadius, color: colors[index])

        if side >= 32 {
            let barHeight = max(1, round(side * 0.045))
            let bar = CGRect(
                x: cell.minX + tile * 0.22,
                y: cell.minY + tile * 0.2,
                width: tile * [0.55, 0.38, 0.7, 0.48][index],
                height: barHeight
            )
            fillRoundedRect(bar, radius: barHeight / 2, color: NSColor(calibratedWhite: 1, alpha: 0.74))
        }
    }
}

func renderAppIconPNG(pixelSize: Int) throws -> Data {
    try bitmap(pixelSize: pixelSize, draw: drawAppIcon)
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
    name: "BeaconAppIcon",
    basePixelSize: 32,
    renderer: renderAppIconPNG
)

print(appIconRoot.path)

import AppKit

struct Candidate {
    let title: String
    let symbol: String
    let note: String
}

let candidates: [Candidate] = [
    .init(title: "Wireless Dot", symbol: "dot.radiowaves.left.and.right", note: "Best menu bar base"),
    .init(title: "Antenna", symbol: "antenna.radiowaves.left.and.right", note: "Connected source"),
    .init(title: "Antenna Circle", symbol: "antenna.radiowaves.left.and.right.circle", note: "Settings sidebar"),
    .init(title: "Sensor", symbol: "sensor.radiowaves.left.and.right", note: "Device hub"),
    .init(title: "Sensor Tag", symbol: "sensor.tag.radiowaves.forward", note: "Tracked device"),
    .init(title: "Keyboard", symbol: "keyboard", note: "Keychron row"),
    .init(title: "Keyboard Fill", symbol: "keyboard.fill", note: "Small-size strong"),
    .init(title: "Keyboard Badge", symbol: "keyboard.badge.ellipsis", note: "Input settings"),
    .init(title: "Battery 100", symbol: "battery.100percent", note: "Battery level"),
    .init(title: "Battery Bolt", symbol: "battery.100percent.bolt", note: "Charging"),
    .init(title: "Battery Block", symbol: "minus.plus.batteryblock", note: "BatteryHub brand"),
    .init(title: "Battery Stack", symbol: "minus.plus.batteryblock.stack", note: "Multi-device hub"),
    .init(title: "AirPods Pro", symbol: "airpods.pro", note: "Audio devices"),
    .init(title: "AirPods Case", symbol: "airpods.pro.chargingcase.wireless", note: "Case battery"),
    .init(title: "AirPods Radio", symbol: "airpods.pro.chargingcase.wireless.radiowaves.left.and.right", note: "Wireless audio"),
    .init(title: "Switch", symbol: "switch.2", note: "Menu bar status"),
    .init(title: "Grid Circle", symbol: "circle.hexagongrid", note: "Neutral hub"),
    .init(title: "Grid Fill", symbol: "circle.hexagongrid.fill", note: "Compact mark")
]

let scale: CGFloat = 2
let columns = 3
let cardWidth: CGFloat = 290
let cardHeight: CGFloat = 150
let margin: CGFloat = 28
let headerHeight: CGFloat = 80
let rows = Int(ceil(Double(candidates.count) / Double(columns)))
let canvasSize = CGSize(
    width: margin * 2 + CGFloat(columns) * cardWidth + CGFloat(columns - 1) * 16,
    height: margin * 2 + headerHeight + CGFloat(rows) * cardHeight + CGFloat(rows - 1) * 16
)

let image = NSImage(size: canvasSize)
image.lockFocus()

NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
    .foregroundColor: NSColor.labelColor
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor.secondaryLabelColor
]
("BatteryHub SF Symbols Candidates" as NSString).draw(
    at: CGPoint(x: margin, y: canvasSize.height - margin - 34),
    withAttributes: titleAttributes
)
("Monochrome, runtime-available symbols. Pick a base, then compose our own mark around it." as NSString).draw(
    at: CGPoint(x: margin, y: canvasSize.height - margin - 58),
    withAttributes: subtitleAttributes
)

let cardFill = NSColor.white.withAlphaComponent(0.86)
let cardStroke = NSColor.black.withAlphaComponent(0.10)
let symbolColor = NSColor.black.withAlphaComponent(0.76)
let mutedColor = NSColor.black.withAlphaComponent(0.54)

for (index, candidate) in candidates.enumerated() {
    let col = index % columns
    let row = index / columns
    let x = margin + CGFloat(col) * (cardWidth + 16)
    let y = canvasSize.height - margin - headerHeight - CGFloat(row + 1) * cardHeight - CGFloat(row) * 16
    let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)
    let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
    cardFill.setFill()
    path.fill()
    cardStroke.setStroke()
    path.lineWidth = 1
    path.stroke()

    if let symbol = NSImage(systemSymbolName: candidate.symbol, accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        configured.isTemplate = true
        symbolColor.set()
        configured.draw(in: CGRect(x: x + 24, y: y + 54, width: 58, height: 58))
    }

    if let smallSymbol = NSImage(systemSymbolName: candidate.symbol, accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let configured = smallSymbol.withSymbolConfiguration(config) ?? smallSymbol
        configured.isTemplate = true
        mutedColor.set()
        configured.draw(in: CGRect(x: x + 242, y: y + 94, width: 22, height: 22))
    }

    let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor.labelColor
    ]
    let symbolAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    let noteAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    (candidate.title as NSString).draw(
        at: CGPoint(x: x + 96, y: y + 94),
        withAttributes: labelAttributes
    )
    (candidate.symbol as NSString).draw(
        in: CGRect(x: x + 96, y: y + 72, width: 170, height: 18),
        withAttributes: symbolAttributes
    )
    (candidate.note as NSString).draw(
        in: CGRect(x: x + 24, y: y + 22, width: cardWidth - 48, height: 18),
        withAttributes: noteAttributes
    )
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render PNG")
}

let output = CommandLine.arguments.dropFirst().first ?? "/tmp/batteryhub-sf-symbol-candidates.png"
try data.write(to: URL(fileURLWithPath: output))
print(output)

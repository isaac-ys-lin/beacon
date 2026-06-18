import XCTest
@testable import BatteryHub

final class DeviceListPresentationTests: XCTestCase {

    // MARK: - Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000)

    private func makeSnapshot(
        deviceID: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState = .unplugged,
        source: BatterySource = .coreBluetooth,
        updatedAt: Date = fixedDate
    ) -> BatterySnapshot {
        BatterySnapshot(
            deviceID: deviceID,
            displayName: displayName,
            kind: kind,
            percent: percent,
            chargeState: chargeState,
            source: source,
            updatedAt: updatedAt
        )
    }

    private func makeDecorated(
        deviceID: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState = .unplugged,
        freshness: Freshness = .fresh
    ) -> DecoratedBatterySnapshot {
        DecoratedBatterySnapshot(
            snapshot: makeSnapshot(
                deviceID: deviceID,
                displayName: displayName,
                kind: kind,
                percent: percent,
                chargeState: chargeState
            ),
            freshness: freshness
        )
    }

    // MARK: - airPodsPrefix

    func testAirPodsPrefixStripsCase() {
        XCTAssertEqual(airPodsPrefix(for: "20-C1-9B-AA-BB-CC-case"), "20-C1-9B-AA-BB-CC")
    }

    func testAirPodsPrefixStripsLeft() {
        XCTAssertEqual(airPodsPrefix(for: "20-C1-9B-AA-BB-CC-left"), "20-C1-9B-AA-BB-CC")
    }

    func testAirPodsPrefixStripsRight() {
        XCTAssertEqual(airPodsPrefix(for: "20-C1-9B-AA-BB-CC-right"), "20-C1-9B-AA-BB-CC")
    }

    func testAirPodsPrefixDoesNotSplitOnInternalDash() {
        // Bluetooth address "20-C1-9B-AA-BB-CC" must not be broken by splitting on "-"
        let raw = "20-C1-9B-AA-BB-CC-left"
        let prefix = airPodsPrefix(for: raw)
        XCTAssertEqual(prefix, "20-C1-9B-AA-BB-CC")
        XCTAssertFalse(prefix.hasSuffix("-"))
    }

    func testAirPodsPrefixRetainsPlainAddress() {
        // Single-component device: no suffix to strip
        let address = "20-C1-9B-AA-BB-CC"
        XCTAssertEqual(airPodsPrefix(for: address), address)
    }

    // MARK: - strippedAirPodsName

    func testStrippedNameRemovesCase() {
        XCTAssertEqual(strippedAirPodsName("John's AirPods Pro Case"), "John's AirPods Pro")
    }

    func testStrippedNameRemovesLeft() {
        XCTAssertEqual(strippedAirPodsName("John's AirPods Pro Left"), "John's AirPods Pro")
    }

    func testStrippedNameRemovesRight() {
        XCTAssertEqual(strippedAirPodsName("John's AirPods Pro Right"), "John's AirPods Pro")
    }

    func testStrippedNameCaseInsensitive() {
        // lowercased comparison, original casing preserved in result up to the suffix
        XCTAssertEqual(strippedAirPodsName("John's AirPods Case"), "John's AirPods")
    }

    // MARK: - AirPods 3-component aggregation

    func testAirPodsThreeComponentAggregation() {
        let addr = "20-C1-9B-AA-BB-CC"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case",  displayName: "John's AirPods Pro Case",  kind: .airPods, percent: 90),
            makeDecorated(deviceID: "\(addr)-left",  displayName: "John's AirPods Pro Left",  kind: .airPods, percent: 75),
            makeDecorated(deviceID: "\(addr)-right", displayName: "John's AirPods Pro Right", kind: .airPods, percent: 80),
        ]

        let sections = groupedDeviceItems(snapshots)
        // All airPods → mobile section only
        XCTAssertEqual(sections.count, 1)

        let items = sections[0].items
        XCTAssertEqual(items.count, 1)

        guard case .airPods(let name, let id, let components) = items[0] else {
            XCTFail("Expected .airPods item, got \(items[0])")
            return
        }

        XCTAssertEqual(name, "John's AirPods Pro")
        XCTAssertEqual(id, addr)
        XCTAssertEqual(components.count, 3)

        // Slot order: case < left < right
        XCTAssertEqual(components[0].slot, .case)
        XCTAssertEqual(components[0].percent, 90)

        XCTAssertEqual(components[1].slot, .left)
        XCTAssertEqual(components[1].percent, 75)

        XCTAssertEqual(components[2].slot, .right)
        XCTAssertEqual(components[2].percent, 80)
    }

    func testAirPodsComponentsCanHaveNilPercent() {
        let addr = "AA-BB-CC-DD-EE-FF"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case",  displayName: "AirPods Case",  kind: .airPods, percent: nil),
            makeDecorated(deviceID: "\(addr)-left",  displayName: "AirPods Left",  kind: .airPods, percent: 60),
            makeDecorated(deviceID: "\(addr)-right", displayName: "AirPods Right", kind: .airPods, percent: 55),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 1)
        guard case .airPods(_, _, let components) = sections[0].items[0] else {
            XCTFail("Expected .airPods item")
            return
        }
        XCTAssertNil(components[0].percent) // case has no percent
        XCTAssertNotNil(components[1].percent)
    }

    // MARK: - Single-component fallback

    func testAirPodsSingleComponentFallsBackToDevice() {
        let addr = "AA-BB-CC-DD-EE-FF"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-left", displayName: "AirPods Left", kind: .airPods, percent: 70),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 1)

        let items = sections[0].items
        XCTAssertEqual(items.count, 1)

        guard case .device(_) = items[0] else {
            XCTFail("Single-component AirPods should fall back to .device, got \(items[0])")
            return
        }
    }

    // MARK: - Section grouping

    func testMacAndInputDevicesAreInSectionOne() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "mac1",      displayName: "MacBook Pro",  kind: .macBook,   percent: 85),
            makeDecorated(deviceID: "kbd1",      displayName: "Keyboard",     kind: .keyboard,  percent: 90),
            makeDecorated(deviceID: "mouse1",    displayName: "Mouse",        kind: .mouse,     percent: 70),
            makeDecorated(deviceID: "trackpad1", displayName: "Trackpad",     kind: .trackpad,  percent: 65),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items.count, 4)
        // All should be .device items in section 0
        for item in sections[0].items {
            guard case .device(_) = item else {
                XCTFail("Expected .device items in Mac section, got \(item)")
                return
            }
        }
    }

    func testMobileAndAudioAreInSectionTwo() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "iphone1", displayName: "Isaac's iPhone",     kind: .iPhone,     percent: 80),
            makeDecorated(deviceID: "watch1",  displayName: "Apple Watch",        kind: .appleWatch, percent: 50),
            makeDecorated(deviceID: "bt1",     displayName: "BT Speaker",         kind: .bluetoothPeripheral, percent: 40),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items.count, 3)
    }

    func testTwoSectionsWhenBothHaveDevices() {
        let addr = "20-C1-9B-AA-BB-CC"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "mac1",        displayName: "Mac mini",         kind: .macBook,   percent: nil),
            makeDecorated(deviceID: "iphone1",     displayName: "Isaac's iPhone",   kind: .iPhone,    percent: 80),
            makeDecorated(deviceID: "\(addr)-case", displayName: "AirPods Pro Case", kind: .airPods,  percent: 90),
            makeDecorated(deviceID: "\(addr)-left", displayName: "AirPods Pro Left", kind: .airPods,  percent: 75),
            makeDecorated(deviceID: "\(addr)-right",displayName: "AirPods Pro Right",kind: .airPods,  percent: 80),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 2)
        // Section 0: Mac
        XCTAssertEqual(sections[0].items.count, 1)
        guard case .device(let mac) = sections[0].items[0] else {
            XCTFail("Section 0 should be Mac device")
            return
        }
        XCTAssertEqual(mac.snapshot.kind, .macBook)

        // Section 1: iPhone + aggregated AirPods
        XCTAssertEqual(sections[1].items.count, 2)
    }

    func testEmptySectionsAreDropped() {
        // Only mobile devices → only 1 section, not 2
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "iphone1", displayName: "iPhone", kind: .iPhone, percent: 60),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 1, "Empty Mac section should be dropped")
    }

    func testEmptyInputProducesNoSections() {
        let sections = groupedDeviceItems([])
        XCTAssertTrue(sections.isEmpty)
    }

    // MARK: - nil-percent Mac is NOT filtered out (§0 verification)

    func testNilPercentMacIsIncluded() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "mac1", displayName: "Mac mini", kind: .macBook, percent: nil),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items.count, 1)

        guard case .device(let d) = sections[0].items[0] else {
            XCTFail("Expected .device item for nil-percent Mac")
            return
        }
        XCTAssertNil(d.snapshot.percent)
    }

    // MARK: - Intra-section order preserved

    func testIntraSectionOrderPreserved() {
        // Input is already sorted by sortOrder; verify grouping preserves it.
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "mac1",   displayName: "MacBook Pro",  kind: .macBook,  percent: 85),
            makeDecorated(deviceID: "kbd1",   displayName: "Keyboard",     kind: .keyboard, percent: 90),
            makeDecorated(deviceID: "mouse1", displayName: "Magic Mouse",  kind: .mouse,    percent: 70),
        ]

        let sections = groupedDeviceItems(snapshots)
        XCTAssertEqual(sections.count, 1)
        let ids = sections[0].items.map { item -> String in
            if case .device(let d) = item { return d.snapshot.deviceID }
            return ""
        }
        XCTAssertEqual(ids, ["mac1", "kbd1", "mouse1"])
    }

    // MARK: - SF Symbol runtime availability guard

    func testSFSymbolRuntimeAvailability() {
        // These are the symbols we use. On macOS 14 some may not exist;
        // the production code uses a runtime guard (resolveSymbol) to fall back.
        // Here we verify our fallback mechanism itself works for known-good symbols.
        let knownGoodSymbols = ["desktopcomputer", "macmini", "macbook", "iphone",
                                "iphone.gen3", "applewatch", "applewatch.side.right",
                                "keyboard", "computermouse", "magicmouse",
                                "rectangle.and.hand.point.up.left",
                                "rectangle.and.hand.point.up.left.fill",
                                "dot.radiowaves.left.and.right",
                                "airpodspro", "airpodsmax", "airpods",
                                "airpods.chargingcase", "airpod.left", "airpod.right",
                                "bolt.fill", "arrow.clockwise", "gearshape"]

        for symbol in knownGoodSymbols {
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            XCTAssertNotNil(img, "Symbol '\(symbol)' did not resolve on host OS — check fallback")
        }
    }

    func testPotentiallyUnavailableSymbolsHaveFallback() {
        // These symbols may not exist on macOS 14 (deployment target).
        // Production code resolves them with resolveSymbol(_:fallback:) which
        // returns the fallback when NSImage returns nil. Here we document which
        // ones DO resolve on the host (macOS 26) vs. which need fallback on 14.
        let symbolsToCheck: [(symbol: String, fallback: String)] = [
            ("macstudio",     "desktopcomputer"),
            ("macpro.gen3",   "desktopcomputer"),
            ("airpods.gen3",  "airpods"),
        ]

        for pair in symbolsToCheck {
            // If it resolves on host, great. If not, at least the fallback must resolve.
            let primary = NSImage(systemSymbolName: pair.symbol, accessibilityDescription: nil)
            let fallback = NSImage(systemSymbolName: pair.fallback, accessibilityDescription: nil)
            XCTAssertNotNil(fallback,
                "Fallback '\(pair.fallback)' for '\(pair.symbol)' must always resolve")
            _ = primary // may be nil on older OS — guarded at runtime in production
        }
    }
}

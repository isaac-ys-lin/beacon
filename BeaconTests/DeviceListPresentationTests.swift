import AppKit
import AppIntents
import SwiftUI
import XCTest
@testable import Beacon

final class DeviceListPresentationTests: XCTestCase {

    // MARK: - Helpers

    private static let fixedDate = Date(timeIntervalSince1970: 1_000)

    private func makeSnapshot(
        deviceID: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState = .unplugged,
        connectionState: ConnectionState = .connected,
        source: BatterySource = .coreBluetooth,
        updatedAt: Date = fixedDate
    ) -> BatterySnapshot {
        BatterySnapshot(
            deviceID: deviceID,
            displayName: displayName,
            kind: kind,
            percent: percent,
            chargeState: chargeState,
            connectionState: connectionState,
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
        freshness: Freshness = .fresh,
        connectionState: ConnectionState = .connected,
        source: BatterySource = .coreBluetooth,
        updatedAt: Date = fixedDate
    ) -> DecoratedBatterySnapshot {
        DecoratedBatterySnapshot(
            snapshot: makeSnapshot(
                deviceID: deviceID,
                displayName: displayName,
                kind: kind,
                percent: percent,
                chargeState: chargeState,
                connectionState: connectionState,
                source: source,
                updatedAt: updatedAt
            ),
            freshness: freshness
        )
    }

    private func isolatedDefaults(name: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "BeaconTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func roundedRGBAComponents(for color: NSColor) -> [Int] {
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? color
        return [
            Int((rgbColor.redComponent * 255).rounded()),
            Int((rgbColor.greenComponent * 255).rounded()),
            Int((rgbColor.blueComponent * 255).rounded()),
            Int((rgbColor.alphaComponent * 255).rounded())
        ]
    }

    private func pixelCoordinate(_ point: Int, backingScale: CGFloat) -> Int {
        Int((CGFloat(point) * backingScale).rounded())
    }

    @MainActor
    private func backingScale(for bitmap: NSBitmapImageRep, in view: NSView) -> CGFloat {
        CGFloat(bitmap.pixelsWide) / view.bounds.width
    }

    private func withAppearanceTheme<T>(
        _ theme: BeaconAppearanceTheme,
        perform work: () throws -> T
    ) rethrows -> T {
        let previousTheme = UserDefaults.standard.string(forKey: BeaconAppearanceTheme.defaultsKey)
        UserDefaults.standard.set(theme.rawValue, forKey: BeaconAppearanceTheme.defaultsKey)
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: BeaconAppearanceTheme.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: BeaconAppearanceTheme.defaultsKey)
            }
        }
        return try work()
    }

    private func withQuickActionPreferences<T>(
        _ preferences: BeaconQuickActionPreferences,
        perform work: () throws -> T
    ) rethrows -> T {
        let previousIDs = UserDefaults.standard.stringArray(forKey: BeaconQuickActionPreferences.enabledActionIDsKey)
        preferences.save()
        defer {
            if let previousIDs {
                UserDefaults.standard.set(previousIDs, forKey: BeaconQuickActionPreferences.enabledActionIDsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: BeaconQuickActionPreferences.enabledActionIDsKey)
            }
        }
        return try work()
    }

    @MainActor
    private func renderedBitmap<V: View>(
        for view: V,
        width: CGFloat,
        height: CGFloat
    ) throws -> (NSHostingView<V>, NSBitmapImageRep) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return (hostingView, bitmap)
    }

    private func sampledColors(
        in bitmap: NSBitmapImageRep,
        xValues: StrideTo<Int>,
        yValues: StrideTo<Int>,
        backingScale: CGFloat
    ) -> [NSColor] {
        xValues.flatMap { x in
            yValues.compactMap { y in
                let pixelX = min(max(pixelCoordinate(x, backingScale: backingScale), 0), bitmap.pixelsWide - 1)
                let pixelY = min(max(pixelCoordinate(y, backingScale: backingScale), 0), bitmap.pixelsHigh - 1)
                return bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB)
            }
        }
    }

    @MainActor
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let current = view as? NSScrollView
        return view.subviews.reduce(current.map { [$0] } ?? []) { partial, subview in
            partial + scrollViews(in: subview)
        }
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

    func testDashboardBatteryDeviceKeepsAirPodsComponentsForSplitDisplay() {
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 53),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 100),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 100),
        ]

        let sections = groupedDeviceItems(snapshots)
        guard case .airPods = sections[0].items[0] else {
            XCTFail("Expected aggregated AirPods item")
            return
        }

        let dashboardDevice = DashboardBatteryDevice(item: sections[0].items[0])

        XCTAssertEqual(dashboardDevice.percent, 53)
        XCTAssertEqual(dashboardDevice.airPodsComponents.map(\.slot), [.case, .left, .right])
        XCTAssertEqual(dashboardDevice.airPodsComponents.map(\.percent), [53, 100, 100])
    }

    func testDashboardBatteryDeviceDropsExpiredAirPodsComponentsFromDisplay() {
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 4, freshness: .expired),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 82),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 79),
        ]

        let sections = groupedDeviceItems(snapshots)
        let dashboardDevice = DashboardBatteryDevice(item: sections[0].items[0])

        XCTAssertEqual(dashboardDevice.percent, 79)
        XCTAssertEqual(dashboardDevice.freshness, .fresh)
        XCTAssertEqual(dashboardDevice.airPodsComponents.map(\.slot), [.left, .right])
        XCTAssertEqual(dashboardDevice.airPodsComponents.map(\.percent), [82, 79])
    }

    func testAirPodsOverviewIgnoresExpiredLowComponent() {
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 4, freshness: .expired),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 82),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 79),
        ]
        let sections = groupedDeviceItems(snapshots)

        let overviewDevices = batteryOverviewDevices(for: sections)
        let summary = batteryOverviewSummary(for: sections, lowBatteryThreshold: 20)

        XCTAssertEqual(overviewDevices.first?.percent, 79)
        XCTAssertEqual(summary.lowBatteryItemCount, 0)
        XCTAssertEqual(summary.lowestPercent, 79)
    }

    func testDashboardBatteryDeviceKeepsAggregatedAirPodsLatestUpdateTime() {
        let addr = "7C-F3-4D-74-56-78"
        let older = Date(timeIntervalSince1970: 2_000)
        let newer = Date(timeIntervalSince1970: 2_120)
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 53, freshness: .stale, updatedAt: older),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 100, freshness: .stale, updatedAt: newer),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 100, freshness: .stale, updatedAt: older),
        ]

        let sections = groupedDeviceItems(snapshots)
        let dashboardDevice = DashboardBatteryDevice(item: sections[0].items[0])

        XCTAssertEqual(dashboardDevice.updatedAt, newer)
        XCTAssertEqual(
            dashboardBatteryStatusText(
                percent: dashboardDevice.percent,
                chargeState: dashboardDevice.chargeState,
                freshness: dashboardDevice.freshness,
                isLow: false,
                showsAirPodsComponents: true,
                updatedAt: dashboardDevice.updatedAt,
                now: newer.addingTimeInterval(12 * 60)
            ),
            "12m ago"
        )
    }

    func testDashboardBatteryDeviceKeepsDeviceUpdateMetadata() {
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let decorated = makeDecorated(
            deviceID: "iphone",
            displayName: "YiSungiPhone",
            kind: .iPhone,
            percent: 80,
            freshness: .stale,
            source: .coreBluetooth,
            updatedAt: updatedAt
        )

        let dashboardDevice = DashboardBatteryDevice(item: .device(decorated))

        XCTAssertEqual(dashboardDevice.updatedAt, updatedAt)
        XCTAssertEqual(dashboardDevice.source, .coreBluetooth)
        XCTAssertEqual(dashboardDevice.provider, .coreBluetoothBatteryService)
    }

    func testDashboardStatusShowsStaleAgeInsteadOfGenericStale() {
        let now = Date(timeIntervalSince1970: 3_000)
        let updatedAt = now.addingTimeInterval(-12 * 60)

        XCTAssertEqual(
            dashboardBatteryStatusText(
                percent: 80,
                chargeState: .unplugged,
                freshness: .stale,
                isLow: false,
                showsAirPodsComponents: false,
                updatedAt: updatedAt,
                now: now
            ),
            "12m ago"
        )
    }

    func testBatteryProviderLabelDistinguishesIPhoneSources() {
        XCTAssertEqual(
            batteryProviderLabel(source: .coreBluetooth, provider: .coreBluetoothBatteryService),
            "Bluetooth Battery Service"
        )
        XCTAssertEqual(
            batteryProviderLabel(source: .ideviceInfo, provider: .ideviceInfo),
            "USB iPhone"
        )
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

    // MARK: - Device display preferences

    func testConfiguredDeviceSectionsPinAndHideItemsWithoutChangingStoreOrder() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 18),
            makeDecorated(deviceID: "trackpad", displayName: "Magic Trackpad", kind: .trackpad, percent: 51),
        ]
        let preferences = DeviceDisplayPreferences(
            pinnedDeviceIDs: ["trackpad"],
            hiddenDeviceIDs: ["mouse"]
        )

        let sections = configuredDeviceSections(snapshots, preferences: preferences)

        XCTAssertEqual(sections.count, 1)
        let ids = sections[0].items.map(\.id)
        XCTAssertEqual(ids, ["trackpad", "keyboard"])
        XCTAssertEqual(groupedDeviceItems(snapshots)[0].items.map(\.id), ["keyboard", "mouse", "trackpad"])
    }

    func testDeviceDisplayPreferencesRoundTripThroughUserDefaults() {
        let defaults = isolatedDefaults()
        let preferences = DeviceDisplayPreferences(
            pinnedDeviceIDs: ["keyboard", "airpods"],
            hiddenDeviceIDs: ["mouse"]
        )

        preferences.save(to: defaults)
        let loaded = DeviceDisplayPreferences.load(from: defaults)

        XCTAssertEqual(loaded, preferences)
    }

    func testDeviceDisplayPreferencesRestoreSingleHiddenItem() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 18),
        ]
        let mouse = groupedDeviceItems(snapshots)[0].items[1]
        let preferences = DeviceDisplayPreferences(
            pinnedDeviceIDs: ["keyboard"],
            hiddenDeviceIDs: ["mouse"]
        )

        let restored = preferences.restoring(mouse)

        XCTAssertEqual(restored.pinnedDeviceIDs, ["keyboard"])
        XCTAssertTrue(restored.hiddenDeviceIDs.isEmpty)
    }

    func testDeviceInspectorItemsSortPinnedVisibleThenHidden() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 18),
            makeDecorated(deviceID: "trackpad", displayName: "Magic Trackpad", kind: .trackpad, percent: 51),
        ]
        let preferences = DeviceDisplayPreferences(
            pinnedDeviceIDs: ["trackpad"],
            hiddenDeviceIDs: ["mouse"]
        )

        let inspectorItems = deviceInspectorItems(snapshots, preferences: preferences)

        XCTAssertEqual(inspectorItems.map(\.id), ["trackpad", "keyboard", "mouse"])
        XCTAssertEqual(inspectorItems.map(\.isPinned), [true, false, false])
        XCTAssertEqual(inspectorItems.map(\.isHidden), [false, false, true])
    }

    func testDashboardSectionsHideDisconnectedDevicesAndInspectorMarksThemHidden() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keychron", displayName: "Keychron K3 Max", kind: .keyboard, percent: 93),
            makeDecorated(
                deviceID: "mouse",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: nil,
                connectionState: .disconnected
            ),
            makeDecorated(
                deviceID: "speaker",
                displayName: "Bluetooth Speaker",
                kind: .bluetoothPeripheral,
                percent: nil,
                connectionState: .disconnected,
                source: .bluetoothUnsupported
            ),
        ]

        let dashboardItems = dashboardDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)
        let inspectorItems = deviceInspectorItems(
            snapshots,
            preferences: DeviceDisplayPreferences()
        )

        XCTAssertEqual(dashboardItems.map(\.displayName), ["Keychron K3 Max"])
        XCTAssertEqual(inspectorItems.map(\.displayName), ["Keychron K3 Max", "Magic Mouse", "Bluetooth Speaker"])
        XCTAssertEqual(inspectorItems.map(\.isHidden), [false, true, true])
        XCTAssertEqual(inspectorItems.map(\.isUnavailable), [false, true, true])
    }

    func testDashboardSectionsHideExpiredBatteryReports() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(
                deviceID: "earfun",
                displayName: "EarFun Air Pro 4",
                kind: .bluetoothPeripheral,
                percent: 90,
                freshness: .expired
            ),
            makeDecorated(
                deviceID: "keychron",
                displayName: "Keychron K3 Max",
                kind: .keyboard,
                percent: 92
            ),
        ]

        let dashboardItems = dashboardDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)

        XCTAssertEqual(dashboardItems.map(\.displayName), ["Keychron K3 Max"])
    }

    func testStatusMenuHidesAirPodsWhenAllComponentsExpired() {
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 53, freshness: .expired),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 82, freshness: .expired),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 79, freshness: .expired),
            makeDecorated(deviceID: "keyboard", displayName: "Keychron K3 Max", kind: .keyboard, percent: 92),
        ]

        let items = statusMenuDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)

        XCTAssertEqual(items.map(\.displayName), ["Keychron K3 Max"])
    }

    func testStatusMenuHidesDisconnectedAirPodsWithLastKnownBatteryReports() {
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 65, connectionState: .disconnected),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 100, connectionState: .disconnected),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 100, connectionState: .disconnected),
            makeDecorated(deviceID: "keyboard", displayName: "Keychron K3 Max", kind: .keyboard, percent: 92),
        ]

        let items = statusMenuDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)

        XCTAssertEqual(items.map(\.displayName), ["Keychron K3 Max"])
    }

    func testInspectorTreatsDisconnectedAirPodsAsUnavailable() {
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 65, connectionState: .disconnected),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 100, connectionState: .disconnected),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 100, connectionState: .disconnected),
        ]

        let inspectorItems = deviceInspectorItems(
            snapshots,
            preferences: DeviceDisplayPreferences()
        )

        XCTAssertEqual(inspectorItems.map(\.displayName), ["Yi Sung’s AirPods Pro"])
        XCTAssertEqual(inspectorItems.map(\.isUnavailable), [true])
        XCTAssertTrue(displayedDeviceInspectorItems(inspectorItems, showHiddenUnavailable: false).isEmpty)
    }

    func testInspectorTreatsFullyExpiredAirPodsAsUnavailable() {
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 53, freshness: .expired),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 82, freshness: .expired),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 79, freshness: .expired),
        ]

        let inspectorItems = deviceInspectorItems(
            snapshots,
            preferences: DeviceDisplayPreferences()
        )

        XCTAssertEqual(inspectorItems.map(\.displayName), ["Yi Sung’s AirPods Pro"])
        XCTAssertEqual(inspectorItems.map(\.isUnavailable), [true])
        XCTAssertTrue(displayedDeviceInspectorItems(inspectorItems, showHiddenUnavailable: false).isEmpty)
    }

    func testInspectorKeepsConnectedDevicesWithoutBatteryReportVisible() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keychron", displayName: "Keychron K3 Max", kind: .keyboard, percent: 89),
            makeDecorated(deviceID: "backlight", displayName: "Keyboard Backlight", kind: .keyboard, percent: nil),
        ]

        let inspectorItems = deviceInspectorItems(
            snapshots,
            preferences: DeviceDisplayPreferences()
        )

        XCTAssertEqual(inspectorItems.map(\.displayName), ["Keychron K3 Max", "Keyboard Backlight"])
        XCTAssertEqual(inspectorItems.map(\.isHidden), [false, false])
        XCTAssertEqual(inspectorItems.map(\.isUserHidden), [false, false])
        XCTAssertEqual(inspectorItems.map(\.isUnavailable), [false, false])
    }

    func testStatusMenuSectionsFallbackToConnectedNoReportDevicesWhenNoBatteryReports() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(
                deviceID: "keyboard",
                displayName: "Magic Keyboard",
                kind: .keyboard,
                percent: nil,
                connectionState: .connected,
                source: .ioBluetooth
            ),
            makeDecorated(
                deviceID: "trackpad",
                displayName: "Magic Trackpad",
                kind: .trackpad,
                percent: nil,
                connectionState: .connected,
                source: .ioBluetooth
            ),
            makeDecorated(
                deviceID: "airpods",
                displayName: "AirPods Pro",
                kind: .airPods,
                percent: nil,
                connectionState: .disconnected,
                source: .bluetoothUnsupported
            )
        ]

        let items = statusMenuDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)

        XCTAssertEqual(items.map(\.displayName), ["Magic Keyboard", "Magic Trackpad"])
    }

    func testStatusMenuFallbackHidesExpiredConnectedDevices() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(
                deviceID: "earfun",
                displayName: "EarFun Air Pro 3",
                kind: .bluetoothPeripheral,
                percent: nil,
                freshness: .expired,
                connectionState: .connected,
                source: .coreBluetooth
            ),
            makeDecorated(
                deviceID: "keyboard",
                displayName: "Magic Keyboard",
                kind: .keyboard,
                percent: nil,
                connectionState: .connected,
                source: .ioBluetooth
            ),
        ]

        let items = statusMenuDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)

        XCTAssertEqual(items.map(\.displayName), ["Magic Keyboard"])
    }

    func testStatusMenuSectionsPreferBatteryReportsOverNoReportFallback() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 89),
            makeDecorated(
                deviceID: "trackpad",
                displayName: "Magic Trackpad",
                kind: .trackpad,
                percent: nil,
                connectionState: .connected,
                source: .ioBluetooth
            )
        ]

        let items = statusMenuDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)

        XCTAssertEqual(items.map(\.displayName), ["Magic Keyboard"])
    }

    func testSettingsDeviceInspectorRowsCanCollapseHiddenUnavailableItems() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keychron", displayName: "Keychron K3 Max", kind: .keyboard, percent: 89),
            makeDecorated(deviceID: "backlight", displayName: "Keyboard Backlight", kind: .keyboard, percent: nil),
            makeDecorated(
                deviceID: "airpods",
                displayName: "Yi Sung's AirPods Pro",
                kind: .airPods,
                percent: nil,
                connectionState: .disconnected
            ),
        ]

        let inspectorItems = deviceInspectorItems(
            snapshots,
            preferences: DeviceDisplayPreferences()
        )

        XCTAssertEqual(
            displayedDeviceInspectorItems(inspectorItems, showHiddenUnavailable: true).map(\.displayName),
            ["Keychron K3 Max", "Keyboard Backlight", "Yi Sung's AirPods Pro"]
        )
        XCTAssertEqual(
            displayedDeviceInspectorItems(inspectorItems, showHiddenUnavailable: false).map(\.displayName),
            ["Keychron K3 Max", "Keyboard Backlight"]
        )
    }

    func testStatusMenuSizingGrowsWithDashboardDeviceCount() {
        let oneDevice = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 1,
            visibleScreenHeight: 1_000
        )
        let fiveDevices = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 5,
            visibleScreenHeight: 1_000
        )

        XCTAssertEqual(oneDevice.width, 386)
        XCTAssertGreaterThan(oneDevice.height, 240)
        XCTAssertGreaterThan(fiveDevices.height, oneDevice.height)
        XCTAssertLessThan(fiveDevices.height, 560)
    }

    func testNativeStatusMenuSizingMatchesRenderedRowChrome() {
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 5,
            visibleScreenHeight: 1_000
        )

        XCTAssertEqual(size.width, 386)
        // Native widget-led chrome: 28 vertical padding + 58 header
        // + (18 list padding + 5 * 58 rows + 4 * 8 row gaps),
        // with settings moved into the header.
        XCTAssertEqual(size.height, 426)
    }

    func testStatusMenuSizingUsesHeaderOnlyHeightWhenEmpty() {
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 0,
            visibleScreenHeight: 1_000
        )

        XCTAssertEqual(size.width, 386)
        XCTAssertEqual(size.height, 86)
    }

    func testStatusWindowConfigurationLoadsDashboardPreferences() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: StatusWindowPreferences.showMenuBarBatteryKey)

        let configuration = StatusWindowConfiguration.load(from: defaults)

        XCTAssertTrue(configuration.showsMenuBarBattery)
    }

    func testStatusMenuSizingUsesNativeWidth() {
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 1,
            visibleScreenHeight: 1_000
        )

        XCTAssertEqual(size.width, 386)
        XCTAssertLessThan(size.height, 560)
    }

    @MainActor
    func testStatusMenuPanelControllerReusesHostingController() {
        let coordinator = StatusMenuPanelController()

        coordinator.install(
            rootView: StatusMenuView(snapshots: [], onRefresh: {}),
            contentSize: NSSize(width: 386, height: 330)
        )
        let firstController = coordinator.hostingController

        coordinator.install(
            rootView: StatusMenuView(snapshots: [], isRefreshing: true, onRefresh: {}),
            contentSize: NSSize(width: 386, height: 360)
        )

        XCTAssertNotNil(firstController)
        XCTAssertTrue(coordinator.hostingController === firstController)
    }

    func testStatusMenuHeaderSubtitlePrioritizesRefreshing() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            statusMenuHeaderSubtitle(
                isRefreshing: true,
                isPreviewingData: false,
                visibleItemCount: 3,
                latestUpdatedAt: now.addingTimeInterval(-12 * 60),
                now: now
            ),
            "Scanning nearby"
        )
    }

    func testStatusMenuHeaderSubtitleKeepsEmptyState() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            statusMenuHeaderSubtitle(
                isRefreshing: false,
                isPreviewingData: false,
                visibleItemCount: 0,
                latestUpdatedAt: now,
                now: now
            ),
            "No reporting devices"
        )
    }

    func testStatusMenuHeaderSubtitleAvoidsLiveFreshnessForPreviewData() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            statusMenuHeaderSubtitle(
                isRefreshing: false,
                isPreviewingData: true,
                visibleItemCount: 3,
                latestUpdatedAt: now,
                now: now
            ),
            "Preview data · 3 devices"
        )
    }

    func testStatusMenuHeaderSubtitleShowsLiveSingleDeviceUpdatedNow() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            statusMenuHeaderSubtitle(
                isRefreshing: false,
                isPreviewingData: false,
                visibleItemCount: 1,
                latestUpdatedAt: now.addingTimeInterval(-12),
                now: now
            ),
            "1 device · Updated now"
        )
    }

    func testStatusMenuHeaderSubtitleShowsLiveMultipleDevicesUpdatedMinutesAgo() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            statusMenuHeaderSubtitle(
                isRefreshing: false,
                isPreviewingData: false,
                visibleItemCount: 3,
                latestUpdatedAt: now.addingTimeInterval(-2 * 60),
                now: now
            ),
            "3 devices · Updated 2m ago"
        )
    }

    func testStatusMenuHeaderLatestUpdateUsesVisibleItemsOnly() {
        let now = Date(timeIntervalSince1970: 10_000)
        let hiddenNewer = makeDecorated(
            deviceID: "hidden",
            displayName: "Hidden Mouse",
            kind: .mouse,
            percent: 88,
            updatedAt: now
        )
        let visibleOlder = makeDecorated(
            deviceID: "visible",
            displayName: "Visible Keyboard",
            kind: .keyboard,
            percent: 72,
            updatedAt: now.addingTimeInterval(-5 * 60)
        )
        let preferences = DeviceDisplayPreferences(hiddenDeviceIDs: ["hidden"])
        let visibleItems = statusMenuDeviceSections(
            [hiddenNewer, visibleOlder],
            preferences: preferences
        ).flatMap(\.items)

        XCTAssertEqual(latestStatusMenuUpdateDate(for: visibleItems), visibleOlder.snapshot.updatedAt)
        XCTAssertEqual(
            statusMenuHeaderSubtitle(
                isRefreshing: false,
                isPreviewingData: false,
                visibleItemCount: visibleItems.count,
                latestUpdatedAt: latestStatusMenuUpdateDate(for: visibleItems),
                now: now
            ),
            "1 device · Updated 5m ago"
        )
    }

    func testStatusMenuHeaderLatestUpdateIgnoresExpiredAirPodsComponents() {
        let now = Date(timeIntervalSince1970: 10_000)
        let addr = "7C-F3-4D-74-56-78"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "Yi Sung’s AirPods Pro Case", kind: .airPods, percent: 4, freshness: .expired, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Yi Sung’s AirPods Pro Left", kind: .airPods, percent: 82, updatedAt: now.addingTimeInterval(-120)),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Yi Sung’s AirPods Pro Right", kind: .airPods, percent: 79, updatedAt: now.addingTimeInterval(-180)),
        ]
        let visibleItems = statusMenuDeviceSections(
            snapshots,
            preferences: DeviceDisplayPreferences()
        ).flatMap(\.items)

        XCTAssertEqual(latestStatusMenuUpdateDate(for: visibleItems), now.addingTimeInterval(-120))
    }

    @MainActor
    func testHeaderControlsRenderCompactRefreshAffordance() throws {
        let view = BeaconHeaderControls(
            theme: .light,
            onOpenSettings: {},
            onRefresh: {},
            onQuit: {},
            isRefreshing: true,
            frameSize: 28,
            settingsGlyphSize: 13,
            refreshGlyphSize: 13,
            spacing: 8
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 116, height: 40)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)
        XCTAssertGreaterThan((pngData ?? Data()).count, 900)
    }

    @MainActor
    func testStatusMenuPanelUsesRoundedContentMaskInsteadOfRectangularShadow() {
        let coordinator = StatusMenuPanelController()
        coordinator.install(
            rootView: StatusMenuView(snapshots: [], onRefresh: {}),
            contentSize: NSSize(width: 386, height: 330)
        )

        XCTAssertEqual(coordinator.panel?.hasShadow, false)
        XCTAssertEqual(coordinator.hostingController?.view.layer?.cornerRadius, NativeMacStyle.popoverCornerRadius)
        XCTAssertEqual(coordinator.hostingController?.view.layer?.masksToBounds, true)
    }

    func testStatusMenuPanelPositioningClampsToVisibleFrame() {
        let frame = StatusMenuPanelPositioning.frame(
            contentSize: NSSize(width: 386, height: 330),
            buttonFrame: NSRect(x: 790, y: 870, width: 24, height: 22),
            visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 900)
        )

        XCTAssertEqual(frame.maxX, 792)
        XCTAssertEqual(frame.maxY, 864)
        XCTAssertEqual(frame.size, NSSize(width: 386, height: 330))
    }

    func testStatusMenuSizingCapsToVisibleScreenHeight() {
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 12,
            visibleScreenHeight: 720
        )

        XCTAssertEqual(size.height, 674)
    }

    // MARK: - Battery overview summary

    func testBatteryOverviewSummaryCountsDeviceSignals() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Mouse", kind: .mouse, percent: 18),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 63, chargeState: .charging),
            makeDecorated(deviceID: "speaker", displayName: "Speaker", kind: .bluetoothPeripheral, percent: 44, freshness: .stale),
        ]

        let summary = batteryOverviewSummary(
            for: groupedDeviceItems(snapshots),
            lowBatteryThreshold: 20
        )

        XCTAssertEqual(summary.reportedItemCount, 4)
        XCTAssertEqual(summary.lowestPercent, 18)
        XCTAssertEqual(summary.lowBatteryItemCount, 1)
        XCTAssertEqual(summary.chargingItemCount, 1)
        XCTAssertEqual(summary.staleItemCount, 1)
    }

    func testBatteryOverviewSummaryTreatsAirPodsAsOneVisibleItem() {
        let addr = "20-C1-9B-AA-BB-CC"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "\(addr)-case", displayName: "AirPods Pro Case", kind: .airPods, percent: 88),
            makeDecorated(deviceID: "\(addr)-left", displayName: "AirPods Pro Left", kind: .airPods, percent: 12),
            makeDecorated(deviceID: "\(addr)-right", displayName: "AirPods Pro Right", kind: .airPods, percent: 33, chargeState: .charging, freshness: .stale),
        ]

        let summary = batteryOverviewSummary(
            for: groupedDeviceItems(snapshots),
            lowBatteryThreshold: 20
        )

        XCTAssertEqual(summary.reportedItemCount, 1)
        XCTAssertEqual(summary.lowestPercent, 12)
        XCTAssertEqual(summary.lowBatteryItemCount, 1)
        XCTAssertEqual(summary.chargingItemCount, 1)
        XCTAssertEqual(summary.staleItemCount, 1)
    }

    func testBatteryOverviewDevicesPrioritizeLowestReportedDevices() {
        let addr = "20-C1-9B-AA-BB-CC"
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 18),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 63),
            makeDecorated(deviceID: "\(addr)-case", displayName: "AirPods Pro Case", kind: .airPods, percent: 88),
            makeDecorated(deviceID: "\(addr)-left", displayName: "AirPods Pro Left", kind: .airPods, percent: 12),
            makeDecorated(deviceID: "\(addr)-right", displayName: "AirPods Pro Right", kind: .airPods, percent: 33, chargeState: .charging, freshness: .stale),
        ]

        let devices = batteryOverviewDevices(for: groupedDeviceItems(snapshots), limit: 3)

        XCTAssertEqual(devices.map(\.displayName), ["AirPods Pro", "Magic Mouse", "Apple Watch"])
        XCTAssertEqual(devices.map(\.percent), [12, 18, 63])
        XCTAssertEqual(devices[0].kind, .airPods)
        XCTAssertEqual(devices[0].chargeState, .charging)
        XCTAssertEqual(devices[0].freshness, .stale)
        XCTAssertNotEqual(devices[0].updatedAt, .distantPast)
    }

    // MARK: - Context menu actions

    func testContextMenuActionsExposeSafeImplementedCommandsFirst() {
        let item = DeviceListItem.device(
            makeDecorated(deviceID: "20-C1-9B-AA-BB-CC", displayName: "Magic Mouse", kind: .mouse, percent: 18)
        )

        let actions = deviceContextMenuActions(for: item)

        XCTAssertEqual(actions.prefix(3), [.batteryAlerts, .options, .refresh])
        XCTAssertTrue(DeviceContextMenuAction.batteryAlerts.isEnabled)
        XCTAssertTrue(DeviceContextMenuAction.options.isEnabled)
        XCTAssertTrue(DeviceContextMenuAction.refresh.isEnabled)
        XCTAssertTrue(DeviceContextMenuAction.pin.isEnabled)
        XCTAssertTrue(DeviceContextMenuAction.disconnect.isEnabled(for: item))
        XCTAssertTrue(DeviceContextMenuAction.remove.isEnabled)
    }

    func testAirPodsContextMenuIncludesAudioControls() {
        let airPods = DeviceListItem.airPods(
            name: "AirPods Pro",
            id: "bluetooth-20-C1-9B-AA-BB-CC",
            components: [
                AirPodsComponent(slot: .left, percent: 72, chargeState: .unplugged, freshness: .fresh, connectionState: .connected, updatedAt: Self.fixedDate),
                AirPodsComponent(slot: .right, percent: 68, chargeState: .unplugged, freshness: .fresh, connectionState: .connected, updatedAt: Self.fixedDate),
            ]
        )

        let actions = deviceContextMenuActions(for: airPods)

        XCTAssertEqual(actions.prefix(3), [.batteryAlerts, .audioControls, .options])
        XCTAssertTrue(DeviceContextMenuAction.audioControls.isEnabled(for: airPods))
        XCTAssertEqual(DeviceContextMenuAction.audioControls.title(for: "AirPods Pro"), "Audio Controls...")
    }

    func testAirPodsAudioPreferencesRoundTripPerDevice() {
        let defaults = isolatedDefaults()
        let deviceID = "bluetooth-20-C1-9B-AA-BB-CC"

        AirPodsAudioPreferences(
            listeningMode: .noiseCancellation,
            microphone: .left
        )
        .save(for: deviceID, defaults: defaults)

        XCTAssertEqual(
            AirPodsAudioPreferences.load(for: deviceID, defaults: defaults),
            AirPodsAudioPreferences(listeningMode: .noiseCancellation, microphone: .left)
        )

        AirPodsAudioPreferences.reset(for: deviceID, defaults: defaults)
        XCTAssertEqual(
            AirPodsAudioPreferences.load(for: deviceID, defaults: defaults),
            AirPodsAudioPreferences()
        )
    }

    func testBluetoothDeviceControlSupportNormalizesKnownAddressFormats() {
        XCTAssertEqual(
            BluetoothDeviceControlSupport.normalizedAddress(from: "bluetooth-20-C1-9B-AA-BB-CC"),
            "20:c1:9b:aa:bb:cc"
        )
        XCTAssertEqual(
            BluetoothDeviceControlSupport.normalizedAddress(from: "20:C1:9B:AA:BB:CC-left"),
            "20:c1:9b:aa:bb:cc"
        )
        XCTAssertNil(BluetoothDeviceControlSupport.normalizedAddress(from: "Magic Mouse"))
        XCTAssertNil(BluetoothDeviceControlSupport.normalizedAddress(from: "not-a-bt-address"))
    }

    func testBluetoothDisconnectIsOnlyEnabledForAddressBackedBluetoothDevices() {
        let airPods = DeviceListItem.airPods(
            name: "AirPods Pro",
            id: "bluetooth-20-C1-9B-AA-BB-CC",
            components: [
                AirPodsComponent(slot: .left, percent: 72, chargeState: .unplugged, freshness: .fresh, connectionState: .connected, updatedAt: Self.fixedDate),
                AirPodsComponent(slot: .right, percent: 68, chargeState: .unplugged, freshness: .fresh, connectionState: .connected, updatedAt: Self.fixedDate),
            ]
        )
        let namedMouse = DeviceListItem.device(
            makeDecorated(deviceID: "Magic Mouse", displayName: "Magic Mouse", kind: .mouse, percent: 18)
        )
        let watch = DeviceListItem.device(
            makeDecorated(deviceID: "20-C1-9B-AA-BB-CC", displayName: "Apple Watch", kind: .appleWatch, percent: 80)
        )

        XCTAssertTrue(BluetoothDeviceControlSupport.canDisconnect(airPods))
        XCTAssertFalse(BluetoothDeviceControlSupport.canDisconnect(namedMouse))
        XCTAssertFalse(BluetoothDeviceControlSupport.canDisconnect(watch))
        XCTAssertTrue(DeviceContextMenuAction.disconnect.isEnabled(for: airPods))
        XCTAssertFalse(DeviceContextMenuAction.disconnect.isEnabled(for: namedMouse))
        XCTAssertFalse(DeviceContextMenuAction.disconnect.isEnabled(for: watch))
    }

    func testBluetoothConnectIsOnlyEnabledForDisconnectedAddressBackedDevices() {
        let disconnectedMouse = DeviceListItem.device(
            makeDecorated(
                deviceID: "bluetooth-20-C1-9B-AA-BB-CC",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: nil,
                connectionState: .disconnected
            )
        )
        let connectedMouse = DeviceListItem.device(
            makeDecorated(
                deviceID: "bluetooth-20-C1-9B-AA-BB-CC",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: 18
            )
        )

        XCTAssertTrue(BluetoothDeviceControlSupport.canConnect(disconnectedMouse))
        XCTAssertFalse(BluetoothDeviceControlSupport.canDisconnect(disconnectedMouse))
        XCTAssertFalse(BluetoothDeviceControlSupport.canConnect(connectedMouse))
        XCTAssertTrue(BluetoothDeviceControlSupport.canDisconnect(connectedMouse))
        XCTAssertTrue(deviceContextMenuActions(for: disconnectedMouse).contains(.connect))
        XCTAssertFalse(deviceContextMenuActions(for: disconnectedMouse).contains(.disconnect))
    }

    func testDeviceControlTargetConnectsLowestVisibleDisconnectedDevice() {
        let snapshots = [
            makeDecorated(
                deviceID: "bluetooth-20-C1-9B-AA-BB-CC",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: nil,
                connectionState: .disconnected
            ),
            makeDecorated(
                deviceID: "bluetooth-AA-BB-CC-DD-EE-FF",
                displayName: "Magic Trackpad",
                kind: .trackpad,
                percent: 24,
                connectionState: .disconnected
            ),
            makeDecorated(
                deviceID: "bluetooth-11-22-33-44-55-66",
                displayName: "Magic Keyboard",
                kind: .keyboard,
                percent: 82
            ),
        ]

        let target = deviceControlTarget(for: .connectNearby, snapshots: snapshots)

        XCTAssertEqual(target?.action, .connect)
        XCTAssertEqual(target?.item.displayName, "Magic Trackpad")
    }

    func testDeviceControlTargetDisconnectsLowestVisibleConnectedDeviceAndSkipsHidden() {
        let snapshots = [
            makeDecorated(
                deviceID: "bluetooth-20-C1-9B-AA-BB-CC",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: 18
            ),
            makeDecorated(
                deviceID: "bluetooth-AA-BB-CC-DD-EE-FF",
                displayName: "Magic Trackpad",
                kind: .trackpad,
                percent: 24
            ),
            makeDecorated(
                deviceID: "watch",
                displayName: "Apple Watch",
                kind: .appleWatch,
                percent: 9
            ),
        ]
        let preferences = DeviceDisplayPreferences(hiddenDeviceIDs: ["bluetooth-20-C1-9B-AA-BB-CC"])

        let target = deviceControlTarget(
            for: .disconnectLowest,
            snapshots: snapshots,
            preferences: preferences
        )

        XCTAssertEqual(target?.action, .disconnect)
        XCTAssertEqual(target?.item.displayName, "Magic Trackpad")
    }

    func testContextMenuActionsSwitchToUnpinForPinnedItems() {
        let item = DeviceListItem.device(
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 18)
        )
        let preferences = DeviceDisplayPreferences(pinnedDeviceIDs: ["mouse"])

        let actions = deviceContextMenuActions(for: item, preferences: preferences)

        XCTAssertTrue(actions.contains(.unpin))
        XCTAssertFalse(actions.contains(.pin))
    }

    func testContextMenuActionTitlesMatchAirBuddyStyleCommands() {
        XCTAssertEqual(DeviceContextMenuAction.batteryAlerts.title(for: "AirPods Pro"), "Battery Alerts...")
        XCTAssertEqual(DeviceContextMenuAction.options.title(for: "AirPods Pro"), "Options")
        XCTAssertEqual(DeviceContextMenuAction.pin.title(for: "AirPods Pro"), "Pin AirPods Pro")
        XCTAssertEqual(DeviceContextMenuAction.unpin.title(for: "AirPods Pro"), "Unpin AirPods Pro")
        XCTAssertEqual(DeviceContextMenuAction.remove.title(for: "AirPods Pro"), "Hide from Beacon")
    }

    func testRefreshDiagnosticsPresentationMapsProviderStatusesToSafeNextSteps() {
        let now = Date(timeIntervalSince1970: 2_000)
        let statuses: [(BatteryProvider, BatteryReadStatus)] = [
            (.ioRegistry, .reported),
            (.systemProfiler, .noReport),
            (.coreBluetoothBatteryService, .unavailable),
            (.ideviceInfo, .timedOut),
            (.coreBluetoothBatteryService, .unauthorized),
            (.ideviceInfo, .commandMissing),
        ]
        let diagnostics = BatteryRefreshDiagnostics(
            attempts: statuses.map { provider, status in
                BatteryProviderAttempt(
                    provider: provider,
                    status: status,
                    candidateCount: status == .reported ? 1 : 0,
                    message: "raw command output should never render",
                    attemptedAt: now
                )
            },
            refreshedAt: now,
            snapshotCount: 1
        )

        let presentation = batteryRefreshDiagnosticsPresentation(diagnostics)

        XCTAssertEqual(presentation.attempts.count, statuses.count)
        XCTAssertEqual(presentation.attempts.map(\.status), statuses.map(\.1))
        XCTAssertEqual(presentation.attempts[0].statusTitle, "Reported")
        XCTAssertEqual(presentation.attempts[1].statusTitle, "No report")
        XCTAssertEqual(presentation.attempts[2].statusTitle, "Unavailable")
        XCTAssertEqual(presentation.attempts[3].statusTitle, "Timed out")
        XCTAssertEqual(presentation.attempts[4].statusTitle, "Permission needed")
        XCTAssertEqual(presentation.attempts[5].statusTitle, "Helper missing")
        XCTAssertEqual(presentation.attempts[3].nextStep, "Try again; a slow source did not answer in time.")
        XCTAssertEqual(presentation.attempts[5].nextStep, "Install the optional iPhone helper, then refresh.")
        XCTAssertFalse(presentation.attempts.contains { $0.explanation.contains("raw command") })
        XCTAssertEqual(presentation.tone, .error)
        XCTAssertEqual(presentation.title, "Partial refresh")
    }

    func testRefreshDiagnosticsPresentationDistinguishesWaitingAndHealthyStates() {
        let waiting = batteryRefreshDiagnosticsPresentation(BatteryRefreshDiagnostics())
        XCTAssertEqual(waiting.tone, .neutral)
        XCTAssertEqual(waiting.title, "Waiting for first refresh")
        XCTAssertTrue(waiting.attempts.isEmpty)

        let noReport = batteryRefreshDiagnosticsPresentation(
            BatteryRefreshDiagnostics(
                attempts: [
                    BatteryProviderAttempt(
                        provider: .ioRegistry,
                        status: .noReport,
                        candidateCount: 0,
                        message: "ignored",
                        attemptedAt: Date(timeIntervalSince1970: 2_500)
                    )
                ],
                refreshedAt: Date(timeIntervalSince1970: 2_500),
                snapshotCount: 0
            )
        )
        XCTAssertEqual(noReport.tone, .neutral)
        XCTAssertEqual(noReport.title, "No battery reports")

        let now = Date(timeIntervalSince1970: 3_000)
        let healthy = batteryRefreshDiagnosticsPresentation(
            BatteryRefreshDiagnostics(
                attempts: [
                    BatteryProviderAttempt(
                        provider: .ioRegistry,
                        status: .reported,
                        candidateCount: 2,
                        message: "ignored",
                        attemptedAt: now
                    ),
                    BatteryProviderAttempt(
                        provider: .ideviceInfo,
                        status: .reported,
                        candidateCount: 1,
                        message: "ignored",
                        attemptedAt: now
                    ),
                ],
                refreshedAt: now,
                snapshotCount: 3
            )
        )
        XCTAssertEqual(healthy.tone, .success)
        XCTAssertEqual(healthy.title, "Refresh healthy")
        XCTAssertEqual(healthy.summary, "All 2 provider checks returned battery data.")
    }

    // MARK: - Per-device alert thresholds

    func testLowBatteryNotifierUsesCustomDeviceThresholdWithGlobalFallback() {
        let defaults = isolatedDefaults()
        defaults.set(20, forKey: LowBatteryNotifier.thresholdDefaultsKey)

        XCTAssertEqual(LowBatteryNotifier.threshold(forDeviceID: "keyboard", defaults: defaults), 20)

        LowBatteryNotifier.setThreshold(35, forDeviceID: "keyboard", defaults: defaults)
        XCTAssertEqual(LowBatteryNotifier.threshold(forDeviceID: "keyboard", defaults: defaults), 35)
        XCTAssertTrue(LowBatteryNotifier.hasCustomThreshold(forDeviceID: "keyboard", defaults: defaults))

        LowBatteryNotifier.resetThreshold(forDeviceID: "keyboard", defaults: defaults)
        XCTAssertEqual(LowBatteryNotifier.threshold(forDeviceID: "keyboard", defaults: defaults), 20)
        XCTAssertFalse(LowBatteryNotifier.hasCustomThreshold(forDeviceID: "keyboard", defaults: defaults))
    }

    func testLowBatteryNotifierFallsBackToAirPodsPrefixThreshold() {
        let defaults = isolatedDefaults()
        defaults.set(20, forKey: LowBatteryNotifier.thresholdDefaultsKey)
        LowBatteryNotifier.setThreshold(30, forDeviceID: "AA-BB-CC", defaults: defaults)

        XCTAssertEqual(LowBatteryNotifier.threshold(forDeviceID: "AA-BB-CC-left", defaults: defaults), 30)
        XCTAssertEqual(LowBatteryNotifier.threshold(forDeviceID: "AA-BB-CC-right", defaults: defaults), 30)
    }

    func testLowBatteryNotifierCreatesLowBatteryEventOnceUntilRecovered() {
        let defaults = isolatedDefaults()
        defaults.set(20, forKey: LowBatteryNotifier.thresholdDefaultsKey)
        let lowSnapshot = makeSnapshot(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18)
        let recoveredSnapshot = makeSnapshot(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 50)

        let firstEvents = LowBatteryNotifier.pendingAlertEvents(for: [lowSnapshot], defaults: defaults)
        let duplicateEvents = LowBatteryNotifier.pendingAlertEvents(for: [lowSnapshot], defaults: defaults)
        _ = LowBatteryNotifier.pendingAlertEvents(for: [recoveredSnapshot], defaults: defaults)
        let nextLowEvents = LowBatteryNotifier.pendingAlertEvents(for: [lowSnapshot], defaults: defaults)

        XCTAssertEqual(firstEvents, [
            BatteryAlertEvent(kind: .lowBattery, deviceID: "watch", displayName: "Apple Watch", percent: 18)
        ])
        XCTAssertTrue(duplicateEvents.isEmpty)
        XCTAssertEqual(nextLowEvents, firstEvents)
    }

    func testChargedAlertRequiresDeviceOptInAndCreatesEventOnceUntilDrained() {
        let defaults = isolatedDefaults()
        let chargingSnapshot = makeSnapshot(
            deviceID: "iphone",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 100,
            chargeState: .charging
        )
        let drainedSnapshot = makeSnapshot(
            deviceID: "iphone",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 80,
            chargeState: .charging
        )

        XCTAssertTrue(LowBatteryNotifier.pendingAlertEvents(for: [chargingSnapshot], defaults: defaults).isEmpty)

        LowBatteryNotifier.setChargedAlertEnabled(true, forDeviceID: "iphone", defaults: defaults)
        let firstEvents = LowBatteryNotifier.pendingAlertEvents(for: [chargingSnapshot], defaults: defaults)
        let duplicateEvents = LowBatteryNotifier.pendingAlertEvents(for: [chargingSnapshot], defaults: defaults)
        _ = LowBatteryNotifier.pendingAlertEvents(for: [drainedSnapshot], defaults: defaults)
        let nextChargedEvents = LowBatteryNotifier.pendingAlertEvents(for: [chargingSnapshot], defaults: defaults)

        XCTAssertEqual(firstEvents, [
            BatteryAlertEvent(kind: .charged, deviceID: "iphone", displayName: "Isaac's iPhone", percent: 100)
        ])
        XCTAssertTrue(duplicateEvents.isEmpty)
        XCTAssertEqual(nextChargedEvents, firstEvents)
    }

    func testChargedAlertTriggersForUnknownChargeStateAtOneHundredPercent() {
        let defaults = isolatedDefaults()
        let snapshot = makeSnapshot(
            deviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 100,
            chargeState: .unknown,
            source: .systemProfiler
        )

        LowBatteryNotifier.setChargedAlertEnabled(
            true,
            forDeviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            defaults: defaults
        )

        XCTAssertEqual(LowBatteryNotifier.pendingAlertEvents(for: [snapshot], defaults: defaults), [
            BatteryAlertEvent(kind: .charged, deviceID: "bluetooth-D1-B3-88-E2-67-CB", displayName: "Keychron K3 Max", percent: 100)
        ])
    }

    func testChargedAlertIsNotMarkedAlertedUntilNotificationSucceeds() {
        let defaults = isolatedDefaults()
        let snapshot = makeSnapshot(
            deviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 100,
            chargeState: .unknown,
            source: .systemProfiler
        )
        LowBatteryNotifier.setChargedAlertEnabled(
            true,
            forDeviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            defaults: defaults
        )

        let firstEvents = LowBatteryNotifier.pendingAlertEventsWithoutMarking(for: [snapshot], defaults: defaults)
        let retryEvents = LowBatteryNotifier.pendingAlertEventsWithoutMarking(for: [snapshot], defaults: defaults)
        _ = LowBatteryNotifier.pendingAlertEvents(for: [snapshot], defaults: defaults)
        let duplicateEvents = LowBatteryNotifier.pendingAlertEventsWithoutMarking(for: [snapshot], defaults: defaults)

        XCTAssertEqual(firstEvents, [
            BatteryAlertEvent(kind: .charged, deviceID: "bluetooth-D1-B3-88-E2-67-CB", displayName: "Keychron K3 Max", percent: 100)
        ])
        XCTAssertEqual(retryEvents, firstEvents)
        XCTAssertTrue(duplicateEvents.isEmpty)
    }

    func testReenablingChargedAlertClearsStaleAlertedState() {
        let defaults = isolatedDefaults()
        let snapshot = makeSnapshot(
            deviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 100,
            chargeState: .unknown,
            source: .systemProfiler
        )

        LowBatteryNotifier.setChargedAlertEnabled(
            true,
            forDeviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            defaults: defaults
        )
        _ = LowBatteryNotifier.pendingAlertEvents(for: [snapshot], defaults: defaults)
        XCTAssertTrue(LowBatteryNotifier.pendingAlertEventsWithoutMarking(for: [snapshot], defaults: defaults).isEmpty)

        LowBatteryNotifier.setChargedAlertEnabled(
            true,
            forDeviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            defaults: defaults
        )

        XCTAssertEqual(LowBatteryNotifier.pendingAlertEventsWithoutMarking(for: [snapshot], defaults: defaults), [
            BatteryAlertEvent(kind: .charged, deviceID: "bluetooth-D1-B3-88-E2-67-CB", displayName: "Keychron K3 Max", percent: 100)
        ])
    }

    func testChargedAlertMigrationClearsPreFixStaleAlertedState() {
        let defaults = isolatedDefaults()
        let snapshot = makeSnapshot(
            deviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 100,
            chargeState: .unknown,
            source: .systemProfiler
        )
        LowBatteryNotifier.setChargedAlertEnabled(
            true,
            forDeviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            defaults: defaults
        )
        defaults.set(true, forKey: "Beacon.chargedBatteryAlerted.bluetooth-D1-B3-88-E2-67-CB")
        defaults.set(1, forKey: LowBatteryNotifier.chargedAlertedStateVersionDefaultsKey)

        XCTAssertEqual(LowBatteryNotifier.pendingAlertEventsWithoutMarking(for: [snapshot], defaults: defaults), [
            BatteryAlertEvent(kind: .charged, deviceID: "bluetooth-D1-B3-88-E2-67-CB", displayName: "Keychron K3 Max", percent: 100)
        ])
        XCTAssertEqual(defaults.integer(forKey: LowBatteryNotifier.chargedAlertedStateVersionDefaultsKey), 2)
    }

    func testChargedAlertFollowsDisplayNameWhenBluetoothIdentifierChanges() {
        let defaults = isolatedDefaults()
        LowBatteryNotifier.setChargedAlertEnabled(
            true,
            forDeviceID: "bluetooth-9D520BEC-A95A-D7F0-1F4E-FDBAD0D5D0F0",
            displayName: "Keychron K3 Max",
            defaults: defaults
        )
        let currentSnapshot = makeSnapshot(
            deviceID: "bluetooth-D1-B3-88-E2-67-CB",
            displayName: "Keychron K3 Max",
            kind: .keyboard,
            percent: 100,
            chargeState: .unknown,
            source: .systemProfiler
        )

        XCTAssertTrue(LowBatteryNotifier.isChargedAlertEnabled(for: currentSnapshot, defaults: defaults))
        XCTAssertEqual(LowBatteryNotifier.pendingAlertEvents(for: [currentSnapshot], defaults: defaults), [
            BatteryAlertEvent(kind: .charged, deviceID: "bluetooth-D1-B3-88-E2-67-CB", displayName: "Keychron K3 Max", percent: 100)
        ])
    }

    func testChargedAlertSettingsReadDisplayNameAlias() {
        let defaults = isolatedDefaults()
        LowBatteryNotifier.setChargedAlertEnabled(
            true,
            forDeviceID: "bluetooth-old-id",
            displayName: "Keychron K3 Max",
            defaults: defaults
        )

        XCTAssertTrue(
            LowBatteryNotifier.isChargedAlertEnabled(
                forDeviceID: "bluetooth-current-id",
                displayName: "Keychron K3 Max",
                defaults: defaults
            )
        )
    }

    func testChargedAlertCanBeDisabledGloballyAndFallsBackToAirPodsPrefix() {
        let defaults = isolatedDefaults()
        defaults.set(false, forKey: LowBatteryNotifier.chargedNotificationsEnabledDefaultsKey)
        LowBatteryNotifier.setChargedAlertEnabled(true, forDeviceID: "AA-BB-CC", defaults: defaults)
        let caseSnapshot = makeSnapshot(
            deviceID: "AA-BB-CC-case",
            displayName: "AirPods Pro Case",
            kind: .airPods,
            percent: 100,
            chargeState: .full
        )

        XCTAssertTrue(LowBatteryNotifier.isChargedAlertEnabled(forDeviceID: "AA-BB-CC-case", defaults: defaults))
        XCTAssertTrue(LowBatteryNotifier.pendingAlertEvents(for: [caseSnapshot], defaults: defaults).isEmpty)

        defaults.set(true, forKey: LowBatteryNotifier.chargedNotificationsEnabledDefaultsKey)
        XCTAssertEqual(LowBatteryNotifier.pendingAlertEvents(for: [caseSnapshot], defaults: defaults), [
            BatteryAlertEvent(kind: .charged, deviceID: "AA-BB-CC-case", displayName: "AirPods Pro Case", percent: 100)
        ])
    }

    func testNotificationCenterAuthorizationStatePresentationMapsSystemStatuses() {
        XCTAssertEqual(NotificationCenterAuthorizationState.from(.notDetermined), .notDetermined)
        XCTAssertEqual(NotificationCenterAuthorizationState.from(.denied), .denied)
        XCTAssertEqual(NotificationCenterAuthorizationState.from(.authorized), .authorized)
        XCTAssertEqual(NotificationCenterAuthorizationState.from(.provisional), .provisional)

        XCTAssertEqual(NotificationCenterAuthorizationState.unknown.title, "Checking")
        XCTAssertEqual(NotificationCenterAuthorizationState.notDetermined.title, "Needs Permission")
        XCTAssertEqual(NotificationCenterAuthorizationState.denied.title, "Disabled")
        XCTAssertEqual(NotificationCenterAuthorizationState.authorized.title, "Allowed")
        XCTAssertEqual(NotificationCenterAuthorizationState.provisional.title, "Limited")

        XCTAssertTrue(NotificationCenterAuthorizationState.notDetermined.canRequestPermission)
        XCTAssertFalse(NotificationCenterAuthorizationState.denied.canRequestPermission)
        XCTAssertTrue(NotificationCenterAuthorizationState.denied.canOpenSystemSettings)
        XCTAssertTrue(NotificationCenterAuthorizationState.authorized.canSendTestNotification)
    }

    func testNotificationCenterAuthorizationStateTreatsDisabledDeliverySettingsAsDenied() {
        XCTAssertEqual(
            NotificationCenterAuthorizationState.from(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                notificationCenterSetting: .disabled
            ),
            .denied
        )
        XCTAssertEqual(
            NotificationCenterAuthorizationState.from(
                authorizationStatus: .authorized,
                alertSetting: .disabled,
                notificationCenterSetting: .enabled
            ),
            .denied
        )
        XCTAssertEqual(
            NotificationCenterAuthorizationState.from(
                authorizationStatus: .authorized,
                alertSetting: .notSupported,
                notificationCenterSetting: .enabled
            ),
            .denied
        )
        XCTAssertEqual(
            NotificationCenterAuthorizationState.from(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                notificationCenterSetting: .notSupported
            ),
            .denied
        )
        XCTAssertEqual(
            NotificationCenterAuthorizationState.from(
                authorizationStatus: .provisional,
                alertSetting: .enabled,
                notificationCenterSetting: .enabled
            ),
            .provisional
        )
    }

    func testNotificationCenterDeliveryResultFormatsCompactStatus() {
        let success = NotificationCenterDeliveryResult.queued("Beacon Test Notification")
        let failure = NotificationCenterDeliveryResult.failed("Notifications are disabled")

        XCTAssertEqual(success.title, "Queued")
        XCTAssertEqual(success.subtitle, "Beacon Test Notification")
        XCTAssertEqual(failure.title, "Could not send")
        XCTAssertEqual(failure.subtitle, "Notifications are disabled")
    }

    func testNotificationPermissionRequestPolicyPromptsWhenAlertPreferenceTurnsOnBeforeAuthorization() {
        XCTAssertEqual(
            NotificationPermissionRequestPolicy.activationAction(
                afterEnablingAlertPreference: true,
                authorizationState: .notDetermined
            ),
            .requestAuthorization
        )
        XCTAssertEqual(
            NotificationPermissionRequestPolicy.activationAction(
                afterEnablingAlertPreference: true,
                authorizationState: .unknown
            ),
            .requestAuthorization
        )
        XCTAssertEqual(
            NotificationPermissionRequestPolicy.activationAction(
                afterEnablingAlertPreference: true,
                authorizationState: .denied
            ),
            .openSystemSettings
        )
        XCTAssertEqual(
            NotificationPermissionRequestPolicy.activationAction(
                afterEnablingAlertPreference: true,
                authorizationState: .authorized
            ),
            .none
        )
        XCTAssertEqual(
            NotificationPermissionRequestPolicy.activationAction(
                afterEnablingAlertPreference: false,
                authorizationState: .notDetermined
            ),
            .none
        )
        XCTAssertTrue(
            NotificationPermissionRequestPolicy.shouldRequestAuthorization(
                afterEnablingAlertPreference: true,
                authorizationState: .notDetermined
            )
        )
        XCTAssertTrue(
            NotificationPermissionRequestPolicy.shouldRequestAuthorization(
                afterEnablingAlertPreference: true,
                authorizationState: .unknown
            )
        )
        XCTAssertFalse(
            NotificationPermissionRequestPolicy.shouldRequestAuthorization(
                afterEnablingAlertPreference: false,
                authorizationState: .notDetermined
            )
        )
        XCTAssertFalse(
            NotificationPermissionRequestPolicy.shouldRequestAuthorization(
                afterEnablingAlertPreference: true,
                authorizationState: .authorized
            )
        )
        XCTAssertFalse(
            NotificationPermissionRequestPolicy.shouldRequestAuthorization(
                afterEnablingAlertPreference: true,
                authorizationState: .denied
            )
        )
    }

    func testBatteryHUDPreferencesDefaultToEnabled() {
        let defaults = isolatedDefaults()

        XCTAssertTrue(BatteryHUDPreferences.isEnabled(defaults: defaults))
        XCTAssertTrue(BatteryHUDPreferences.isEnabled(for: .lowBattery, defaults: defaults))
        XCTAssertTrue(BatteryHUDPreferences.isEnabled(for: .charged, defaults: defaults))
        XCTAssertTrue(BatteryHUDPreferences.isAutoDismissEnabled(defaults: defaults))
        XCTAssertFalse(BatteryHUDPreferences.showsDismissButton(defaults: defaults))
        XCTAssertEqual(BatteryHUDPreferences.dismissDelaySeconds(defaults: defaults), 4)

        defaults.set(false, forKey: BatteryHUDPreferences.showActionHUDKey)
        XCTAssertFalse(BatteryHUDPreferences.isEnabled(defaults: defaults))
        XCTAssertFalse(BatteryHUDPreferences.isEnabled(for: .lowBattery, defaults: defaults))
        XCTAssertFalse(BatteryHUDPreferences.isEnabled(for: .charged, defaults: defaults))
    }

    func testBatteryHUDPreferencesCanDisableIndividualEvents() {
        let defaults = isolatedDefaults()

        defaults.set(false, forKey: BatteryHUDPreferences.lowBatteryHUDEnabledKey)

        XCTAssertFalse(BatteryHUDPreferences.isEnabled(for: .lowBattery, defaults: defaults))
        XCTAssertTrue(BatteryHUDPreferences.isEnabled(for: .charged, defaults: defaults))
    }

    func testBatteryHUDPreferencesClampDismissDelayAndDisableBehaviors() {
        let defaults = isolatedDefaults()

        defaults.set(1.5, forKey: BatteryHUDPreferences.dismissDelaySecondsKey)
        XCTAssertEqual(BatteryHUDPreferences.dismissDelaySeconds(defaults: defaults), 2)

        defaults.set(12.0, forKey: BatteryHUDPreferences.dismissDelaySecondsKey)
        XCTAssertEqual(BatteryHUDPreferences.dismissDelaySeconds(defaults: defaults), 10)

        defaults.set(false, forKey: BatteryHUDPreferences.autoDismissEnabledKey)
        defaults.set(false, forKey: BatteryHUDPreferences.showDismissButtonKey)

        XCTAssertFalse(BatteryHUDPreferences.isAutoDismissEnabled(defaults: defaults))
        XCTAssertFalse(BatteryHUDPreferences.showsDismissButton(defaults: defaults))
    }

    func testQuickActionPreferencesDefaultToSafeEnabledActions() {
        let preferences = BeaconQuickActionPreferences()

        XCTAssertTrue(preferences.isEnabled(.showDashboard))
        XCTAssertTrue(preferences.isEnabled(.refreshBatteries))
        XCTAssertFalse(preferences.isEnabled(.openSettings))
        XCTAssertFalse(preferences.isEnabled(.addDevice))
        XCTAssertFalse(preferences.isEnabled(.openBluetoothSettings))
        XCTAssertFalse(preferences.isEnabled(.connectNearbyDevice))
        XCTAssertFalse(preferences.isEnabled(.disconnectLowestDevice))
        XCTAssertFalse(preferences.isEnabled(.transferToMac))
        XCTAssertEqual(BeaconQuickAction.showDashboard.shortcut?.displayText, "⌥⌘B")
        XCTAssertEqual(BeaconQuickAction.connectNearbyDevice.shortcut?.displayText, "⌥⌘N")
        XCTAssertEqual(BeaconQuickAction.disconnectLowestDevice.shortcut?.displayText, "⌥⌘X")
        XCTAssertNil(BeaconQuickAction.transferToMac.shortcut)
    }

    func testQuickActionPreferencesRoundTripAndFilterUnsupportedActions() {
        let defaults = isolatedDefaults()
        let preferences = BeaconQuickActionPreferences()
            .setting(false, for: .showDashboard)
            .setting(true, for: .openSettings)
            .setting(true, for: .connectNearbyDevice)
            .setting(true, for: .transferToMac)

        preferences.save(to: defaults)

        let restored = BeaconQuickActionPreferences.load(from: defaults)
        XCTAssertFalse(restored.isEnabled(.showDashboard))
        XCTAssertTrue(restored.isEnabled(.refreshBatteries))
        XCTAssertTrue(restored.isEnabled(.openSettings))
        XCTAssertTrue(restored.isEnabled(.connectNearbyDevice))
        XCTAssertFalse(restored.isEnabled(.transferToMac))
    }

    func testQuickActionSettingsSummaryReportsSupportedEnabledAndExcludedActions() {
        let preferences = BeaconQuickActionPreferences(
            enabledActionIDs: [
                BeaconQuickAction.showDashboard.id,
                BeaconQuickAction.openSettings.id,
                BeaconQuickAction.transferToMac.id
            ]
        )

        let summary = quickActionSettingsSummary(for: preferences)

        XCTAssertEqual(summary.supportedActionCount, 7)
        XCTAssertEqual(summary.defaultEnabledActionCount, 2)
        XCTAssertEqual(summary.enabledSupportedActions, [.showDashboard, .openSettings])
        XCTAssertEqual(summary.unsupportedActions, [.transferToMac])
        XCTAssertEqual(summary.disabledSupportedActions.count, 5)
        XCTAssertFalse(summary.enabledSupportedActions.contains(.transferToMac))
    }

    @MainActor
    func testBeaconAppShortcutsExposeSupportedAutomationActions() {
        let shortcutCount = BeaconAppShortcuts.appShortcuts.count

        XCTAssertEqual(shortcutCount, 10)
        XCTAssertNil(BeaconQuickAction.transferToMac.shortcut)
    }

    @MainActor
    func testBeaconIntentBridgeRunsSupportedActionsOnly() {
        var handledActions: [BeaconQuickAction] = []
        BeaconIntentBridge.shared.register(
            handler: { action in
                handledActions.append(action)
            },
            snapshotProvider: { [] }
        )

        XCTAssertTrue(BeaconIntentBridge.shared.perform(.refreshBatteries))
        XCTAssertFalse(BeaconIntentBridge.shared.perform(.transferToMac))
        XCTAssertEqual(handledActions, [.refreshBatteries])
    }

    @MainActor
    func testBeaconIntentBridgeProvidesSnapshotsForReadOnlyShortcuts() {
        let snapshots = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18),
        ]

        BeaconIntentBridge.shared.register(
            handler: { _ in },
            snapshotProvider: { snapshots }
        )

        XCTAssertEqual(BeaconIntentBridge.shared.snapshots(), snapshots)
    }

    func testBeaconShortcutSummaryFormatsUsefulAutomationText() {
        let snapshots = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31, freshness: .stale),
            makeDecorated(
                deviceID: "watch",
                displayName: "Apple Watch",
                kind: .appleWatch,
                percent: 18,
                chargeState: .unplugged
            ),
            makeDecorated(
                deviceID: "iphone",
                displayName: "Isaac's iPhone",
                kind: .iPhone,
                percent: 64,
                chargeState: .charging
            ),
        ]

        let summary = BeaconShortcutSnapshotFormatter.summary(
            for: snapshots,
            lowBatteryThreshold: 20
        )

        XCTAssertEqual(summary.reportedDeviceCount, 4)
        XCTAssertEqual(summary.lowestBatteryLine, "Apple Watch 18%")
        XCTAssertEqual(summary.lowBatteryLines, ["Apple Watch 18%"])
        XCTAssertEqual(summary.chargingLines, ["Isaac's iPhone 64%"])
        XCTAssertEqual(summary.staleDeviceCount, 1)
        XCTAssertEqual(
            summary.summaryText,
            "Beacon: 4 reporting devices. Lowest: Apple Watch 18%. Low battery: Apple Watch 18%. Charging: Isaac's iPhone 64%. Stale reports: 1."
        )
        XCTAssertEqual(
            BeaconShortcutSnapshotFormatter.lowBatteryText(
                for: snapshots,
                lowBatteryThreshold: 20
            ),
            "Apple Watch 18%"
        )
    }

    func testBeaconShortcutTrendSummaryUsesLocalHistory() {
        let defaults = isolatedDefaults()
        let base = Date(timeIntervalSince1970: 2_000)
        let snapshots = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31),
        ]

        BatteryHistoryStore.record(
            [
                BatterySnapshot(
                    deviceID: "keyboard",
                    displayName: "Magic Keyboard",
                    kind: .keyboard,
                    percent: 87,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: base
                ),
                BatterySnapshot(
                    deviceID: "keyboard",
                    displayName: "Magic Keyboard",
                    kind: .keyboard,
                    percent: 82,
                    chargeState: .unplugged,
                    source: .coreBluetooth,
                    updatedAt: base.addingTimeInterval(3_600)
                ),
            ],
            now: base.addingTimeInterval(3_600),
            defaults: defaults
        )

        XCTAssertEqual(
            BeaconShortcutSnapshotFormatter.batteryTrendText(
                for: snapshots,
                defaults: defaults
            ),
            "Magic Keyboard: -5% trend, range 82%-87% across 2 reports."
        )
    }

    func testBeaconShortcutTrendSummaryFallsBackWhileCollecting() {
        XCTAssertEqual(
            BeaconShortcutSnapshotFormatter.batteryTrendText(
                for: [
                    makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82)
                ],
                defaults: isolatedDefaults()
            ),
            "No battery trends yet. Beacon builds trends as reports arrive."
        )
    }

    // MARK: - SF Symbol runtime availability guard

    func testSFSymbolRuntimeAvailability() {
        // These are the symbols we use. On macOS 14 some may not exist;
        // the production code uses a runtime guard (resolveSymbol) to fall back.
        // Here we verify our fallback mechanism itself works for known-good symbols.
        let knownGoodSymbols = ["desktopcomputer", "macmini", "macbook", "iphone",
                                "iphone.gen3", "applewatch", "applewatch.side.right",
                                "keyboard", "computermouse", "magicmouse",
                                "macwindow", "rectangle", "circle.fill",
                                "rectangle.and.hand.point.up.left",
                                "rectangle.and.hand.point.up.left.fill",
                                "rectangle.grid.3x2.fill",
                                "dot.radiowaves.left.and.right",
                                "airpodspro", "airpodsmax", "airpods", "headphones",
                                "airpods.chargingcase", "airpod.left", "airpod.right",
                                "l.circle", "r.circle",
                                "battery.25", "battery.100", "bolt.fill", "bell.badge", "bell.slash",
                                "bell.badge.fill", "bell.slash.fill",
                                "checkmark.circle.fill", "checkmark.icloud", "clock.badge.exclamationmark",
                                "arrow.clockwise", "gearshape", "info.circle", "xmark.circle",
                                "slider.horizontal.3", "pin", "pin.fill", "pin.slash",
                                "bolt.horizontal.circle", "minus.circle",
                                "eye", "eye.slash", "arrow.uturn.backward", "xmark",
                                "rectangle.grid.2x2", "rectangle.grid.3x2",
                                "plus", "keyboard"]

        for symbol in knownGoodSymbols {
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            XCTAssertNotNil(img, "Symbol '\(symbol)' did not resolve on host OS — check fallback")
        }
    }

    func testBeaconPrimarySymbolStaysSeparateFromBluetoothSymbol() {
        XCTAssertEqual(
            BeaconSymbols.app,
            resolveSymbol("rectangle.grid.2x2", fallback: "rectangle.grid.3x2")
        )
        XCTAssertNotEqual(BeaconSymbols.app, BeaconSymbols.bluetooth)
    }

    func testBluetoothSettingsTemplateUsesNativeAppKitSymbol() {
        let template = NSImage(named: NSImage.Name("NSBluetoothTemplate"))
        XCTAssertNotNil(template)
    }

    func testKeyboardDevicesUseKeyboardSymbol() {
        XCTAssertEqual(
            deviceSymbolName(for: .keyboard, displayName: "Keychron K3 Max"),
            "keyboard"
        )
        XCTAssertEqual(
            deviceSymbolName(for: .keyboard, displayName: "Magic Keyboard"),
            "keyboard"
        )
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
            ("ear.badge.waveform", "ear"),
            ("speaker.wave.2", "gearshape"),
            ("waveform", "circle.fill"),
            ("mic", "circle.fill"),
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

    // MARK: - Menu bar battery summary

    func testMenuBarBatteryTextUsesLowestAvailablePercent() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "mouse", displayName: "Mouse", kind: .mouse, percent: 41),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 63),
        ]

        XCTAssertEqual(MenuBarBatteryFormatter.menuBarText(for: snapshots), "41%")
    }

    func testMenuBarBatteryTextSkipsExpiredAndUnknownPercent() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Keyboard", kind: .keyboard, percent: nil),
            makeDecorated(deviceID: "mouse", displayName: "Mouse", kind: .mouse, percent: 12, freshness: .expired),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 57),
        ]

        XCTAssertEqual(MenuBarBatteryFormatter.menuBarText(for: snapshots), "57%")
    }

    func testMenuBarBatteryTextSkipsDisconnectedLastKnownPercent() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "airpods-case", displayName: "AirPods Case", kind: .airPods, percent: 65, connectionState: .disconnected),
            makeDecorated(deviceID: "keyboard", displayName: "Keyboard", kind: .keyboard, percent: 82),
        ]

        XCTAssertEqual(MenuBarBatteryFormatter.menuBarText(for: snapshots), "82%")
    }

    func testMenuBarBatteryTextReturnsNilWhenNoFreshPercentExists() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Keyboard", kind: .keyboard, percent: nil),
            makeDecorated(deviceID: "mouse", displayName: "Mouse", kind: .mouse, percent: 18, freshness: .expired),
        ]

        XCTAssertNil(MenuBarBatteryFormatter.menuBarText(for: snapshots))
    }

    func testMenuBarStatusIconUsesReadableMenuBarSizing() {
        XCTAssertEqual(BeaconStatusIconImage.designReferenceAssetName, BeaconSymbols.headerLogoAsset)
        XCTAssertEqual(BeaconMenuBarMetrics.iconSide, 24)
        XCTAssertEqual(BeaconMenuBarMetrics.imageOnlyLength, 24)

        let image = BeaconStatusIconImage.make()
        XCTAssertEqual(image.size.width, BeaconMenuBarMetrics.iconSide, accuracy: 0.01)
        XCTAssertEqual(image.size.height, BeaconMenuBarMetrics.iconSide, accuracy: 0.01)
        XCTAssertTrue(image.isTemplate)
    }

    // MARK: - Runtime-adjacent render smoke test

    func testDesktopWidgetReuseFrameDoesNotDriftWhenStyleIsUnchanged() {
        let currentFrame = NSRect(x: 916, y: 492, width: 318, height: 336)

        let reusedFrame = DesktopWidgetWindowPlacement.reusedFrame(
            currentFrame: currentFrame,
            style: .expanded
        )

        XCTAssertEqual(reusedFrame.origin.x, currentFrame.origin.x, accuracy: 0.01)
        XCTAssertEqual(reusedFrame.origin.y, currentFrame.origin.y, accuracy: 0.01)
        XCTAssertEqual(reusedFrame.width, currentFrame.width, accuracy: 0.01)
        XCTAssertEqual(reusedFrame.height, currentFrame.height, accuracy: 0.01)
    }

    func testDesktopWidgetReuseFramePreservesTopRightWhenStyleChanges() {
        let currentFrame = NSRect(x: 916, y: 492, width: 318, height: 336)

        let reusedFrame = DesktopWidgetWindowPlacement.reusedFrame(
            currentFrame: currentFrame,
            style: .compact
        )

        XCTAssertEqual(reusedFrame.maxX, currentFrame.maxX, accuracy: 0.01)
        XCTAssertEqual(reusedFrame.maxY, currentFrame.maxY, accuracy: 0.01)
        XCTAssertEqual(reusedFrame.width, DesktopWidgetStyle.compact.width, accuracy: 0.01)
        XCTAssertEqual(reusedFrame.height, DesktopWidgetStyle.compact.height, accuracy: 0.01)
    }

    func testDesktopWidgetFrameClampKeepsWidgetInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 900, height: 600)
        let offscreenFrame = NSRect(x: 760, y: -48, width: 318, height: 336)

        let clampedFrame = DesktopWidgetWindowPlacement.clampedFrame(
            offscreenFrame,
            in: visibleFrame
        )

        XCTAssertEqual(clampedFrame.maxX, visibleFrame.maxX, accuracy: 0.01)
        XCTAssertEqual(clampedFrame.minY, visibleFrame.minY, accuracy: 0.01)
        XCTAssertEqual(clampedFrame.width, offscreenFrame.width, accuracy: 0.01)
        XCTAssertEqual(clampedFrame.height, offscreenFrame.height, accuracy: 0.01)
    }

    @MainActor
    func testDesktopWidgetControllerDoesNotDriftAcrossCloseAndReopen() {
        let defaults = UserDefaults.standard
        let showKey = DesktopWidgetPreferences.showDesktopWidgetKey
        let styleKey = DesktopWidgetPreferences.widgetStyleKey
        let originalShowValue = defaults.object(forKey: showKey)
        let originalStyleValue = defaults.object(forKey: styleKey)
        defaults.set(true, forKey: showKey)
        defaults.set(DesktopWidgetStyle.expanded.rawValue, forKey: styleKey)
        defer {
            if let originalShowValue {
                defaults.set(originalShowValue, forKey: showKey)
            } else {
                defaults.removeObject(forKey: showKey)
            }
            if let originalStyleValue {
                defaults.set(originalStyleValue, forKey: styleKey)
            } else {
                defaults.removeObject(forKey: styleKey)
            }
        }

        let now = Date()
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Keychron K3 Max", kind: .keyboard, percent: 82, updatedAt: now),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18, updatedAt: now),
        ]
        let controller = BeaconDesktopWidgetController()

        controller.update(
            snapshots: snapshots,
            onOpenSettings: {}
        )
        guard let firstFrame = controller.debugWindowFrame else {
            XCTFail("Expected desktop widget window frame")
            return
        }
        XCTAssertTrue(controller.debugContentViewMasksToBounds)
        XCTAssertTrue(controller.debugHostingViewMasksToBounds)

        controller.close()
        controller.update(
            snapshots: snapshots,
            onOpenSettings: {}
        )
        guard let secondFrame = controller.debugWindowFrame else {
            XCTFail("Expected desktop widget window frame after reopening")
            return
        }
        XCTAssertTrue(controller.debugContentViewMasksToBounds)
        XCTAssertTrue(controller.debugHostingViewMasksToBounds)
        controller.close()

        XCTAssertEqual(secondFrame.origin.x, firstFrame.origin.x, accuracy: 0.01)
        XCTAssertEqual(secondFrame.origin.y, firstFrame.origin.y, accuracy: 0.01)
        XCTAssertEqual(secondFrame.width, firstFrame.width, accuracy: 0.01)
        XCTAssertEqual(secondFrame.height, firstFrame.height, accuracy: 0.01)
    }

    @MainActor
    func testBeaconSettingsCardSurfaceModifierRendersNonBlankImage() throws {
        let view = Text("Settings surface")
            .font(DesignTokens.Typography.captionEmphasis)
            .padding(18)
            .frame(width: 220, height: 72)
            .beaconSettingsCardSurface()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 72)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let scale = backingScale(for: bitmap, in: hostingView)

        let sampledColors = stride(from: 8, to: Int(hostingView.bounds.width), by: 16).flatMap { x in
            stride(from: 8, to: Int(hostingView.bounds.height), by: 16).compactMap { y in
                bitmap.colorAt(
                    x: pixelCoordinate(x, backingScale: scale),
                    y: pixelCoordinate(y, backingScale: scale)
                )?.usingColorSpace(.deviceRGB)
            }
        }

        XCTAssertGreaterThan(sampledColors.filter { $0.alphaComponent > 0.05 }.count, 8)
        XCTAssertGreaterThan(
            Set(sampledColors.map { color in
                [
                    Int((color.redComponent * 255).rounded()),
                    Int((color.greenComponent * 255).rounded()),
                    Int((color.blueComponent * 255).rounded()),
                    Int((color.alphaComponent * 255).rounded())
                ]
            }).count,
            1
        )
    }

    @MainActor
    func testBatteryDesktopWidgetRenderProducesNonBlankImage() throws {
        let now = Date()
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Keychron K3 Max", kind: .keyboard, percent: 82, updatedAt: now),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 24, freshness: .stale, updatedAt: now),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18, source: .coreBluetooth, updatedAt: now),
            makeDecorated(deviceID: "iphone", displayName: "Isaac's iPhone", kind: .iPhone, percent: 64, chargeState: .charging, source: .coreBluetooth, updatedAt: now),
        ]

        let view = BatteryDesktopWidgetView(
            snapshots: snapshots,
            style: .expanded,
            onOpenSettings: {}
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: DesktopWidgetStyle.expanded.width, height: DesktopWidgetStyle.expanded.height)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-desktop-widget-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 18_000)
    }

    @MainActor
    func testBeaconDashboardSettingsRenderProducesDesktopWidgetPreview() throws {
        UserDefaults.standard.set(true, forKey: DesktopWidgetPreferences.showDesktopWidgetKey)
        UserDefaults.standard.set(DesktopWidgetStyle.expanded.rawValue, forKey: DesktopWidgetPreferences.widgetStyleKey)
        defer {
            UserDefaults.standard.removeObject(forKey: DesktopWidgetPreferences.showDesktopWidgetKey)
            UserDefaults.standard.removeObject(forKey: DesktopWidgetPreferences.widgetStyleKey)
        }

        let view = BeaconSettingsView(
            snapshots: [
                makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
                makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 24),
                makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18),
            ],
            onRefresh: {},
            initialPane: .dashboard
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-dashboard-settings-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testStatusMenuViewPreviewRenderProducesNonBlankImage() throws {
        let addr = "AA-BB-CC-DD-EE-FF"
        let now = Date()
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "mac", displayName: "MacBook Pro", kind: .macBook, percent: nil, source: .macPowerSource, updatedAt: now),
            makeDecorated(deviceID: "keyboard", displayName: "Keychron K3 Max", kind: .keyboard, percent: 82, updatedAt: now),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31, updatedAt: now),
            makeDecorated(deviceID: "iphone", displayName: "Isaac's iPhone", kind: .iPhone, percent: 64, chargeState: .charging, source: .coreBluetooth, updatedAt: now),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18, source: .coreBluetooth, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-case", displayName: "Isaac's AirPods Pro Case", kind: .airPods, percent: 90, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Isaac's AirPods Pro Left", kind: .airPods, percent: 72, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Isaac's AirPods Pro Right", kind: .airPods, percent: 68, updatedAt: now),
        ]

        let view = StatusMenuView(snapshots: snapshots, onRefresh: {})
        let hostingView = NSHostingView(rootView: view)
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 5,
            visibleScreenHeight: 1_000
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-status-menu-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 20_000)
    }

    @MainActor
    func testStatusMenuViewDarkThemeRenderProducesNonBlankImage() throws {
        let previousTheme = UserDefaults.standard.string(forKey: BeaconAppearanceTheme.defaultsKey)
        UserDefaults.standard.set(BeaconAppearanceTheme.dark.rawValue, forKey: BeaconAppearanceTheme.defaultsKey)
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: BeaconAppearanceTheme.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: BeaconAppearanceTheme.defaultsKey)
            }
        }

        let addr = "AA-BB-CC-DD-EE-FF"
        let now = Date()
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "mac", displayName: "MacBook Pro", kind: .macBook, percent: nil, source: .macPowerSource, updatedAt: now),
            makeDecorated(deviceID: "keyboard", displayName: "Keychron K3 Max", kind: .keyboard, percent: 82, updatedAt: now),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31, updatedAt: now),
            makeDecorated(deviceID: "iphone", displayName: "Isaac's iPhone", kind: .iPhone, percent: 64, chargeState: .charging, source: .coreBluetooth, updatedAt: now),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18, source: .coreBluetooth, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-case", displayName: "Isaac's AirPods Pro Case", kind: .airPods, percent: 90, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Isaac's AirPods Pro Left", kind: .airPods, percent: 72, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Isaac's AirPods Pro Right", kind: .airPods, percent: 68, updatedAt: now),
        ]

        let view = StatusMenuView(snapshots: snapshots, onRefresh: {})
        let hostingView = NSHostingView(rootView: view)
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 5,
            visibleScreenHeight: 1_000
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-status-menu-render-dark.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 20_000)
    }

    @MainActor
    func testStatusMenuViewRefreshingRenderProducesNonBlankImage() throws {
        let view = StatusMenuView(
            snapshots: [],
            isRefreshing: true,
            onRefresh: {}
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 386, height: 300)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-status-menu-refreshing-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        // With no devices this state renders header-only, and PNG size scales
        // with the backing store (Retina 2x locally, 1x on CI runners, ~10KB).
        // A blank render of this frame is under 2KB, so 6KB still proves
        // non-blank content without depending on display scale.
        XCTAssertGreaterThan((pngData ?? Data()).count, 6_000)
    }

    @MainActor
    func testStatusMenuViewPreviewDataModeRenderProducesNonBlankImage() throws {
        let now = Date()
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82, updatedAt: now),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31, updatedAt: now),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18, source: .coreBluetooth, updatedAt: now),
        ]

        let view = StatusMenuView(
            snapshots: snapshots,
            isPreviewingData: true,
            onRefresh: {}
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 386, height: 370)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-status-menu-preview-data-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 18_000)
    }

    @MainActor
    func testBeaconSettingsWindowRenderProducesNonBlankImage() throws {
        let addr = "AA-BB-CC-DD-EE-FF"
        let now = Date()
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82, updatedAt: now),
            makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31, updatedAt: now),
            makeDecorated(deviceID: "iphone", displayName: "Isaac's iPhone", kind: .iPhone, percent: 100, chargeState: .full, source: .coreBluetooth, updatedAt: now),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18, source: .coreBluetooth, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-case", displayName: "Isaac's AirPods Pro Case", kind: .airPods, percent: 90, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Isaac's AirPods Pro Left", kind: .airPods, percent: 72, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Isaac's AirPods Pro Right", kind: .airPods, percent: 68, updatedAt: now),
        ]

        let view = BeaconSettingsView(snapshots: snapshots, onRefresh: {})
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-settings-window-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testBeaconSettingsWindowRefreshingRenderProducesNonBlankImage() throws {
        let view = BeaconSettingsView(
            snapshots: [
                makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
                makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31),
            ],
            isRefreshing: true,
            onRefresh: {}
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-settings-refreshing-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testBeaconSettingsWindowCanRenderAirPodsAudioControls() throws {
        let addr = "AA-BB-CC-DD-EE-FF"
        let now = Date()
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-case", displayName: "Isaac's AirPods Pro Case", kind: .airPods, percent: 90, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-left", displayName: "Isaac's AirPods Pro Left", kind: .airPods, percent: 72, updatedAt: now),
            makeDecorated(deviceID: "\(addr)-right", displayName: "Isaac's AirPods Pro Right", kind: .airPods, percent: 68, updatedAt: now),
        ]

        AirPodsAudioPreferences(
            listeningMode: .transparency,
            microphone: .right
        )
        .save(for: addr)
        defer {
            AirPodsAudioPreferences.reset(for: addr)
        }

        let view = BeaconSettingsView(
            snapshots: snapshots,
            onRefresh: {},
            initialPane: .devices,
            initialSelectedDeviceID: addr
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-airpods-settings-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testBeaconSettingsWindowCanRenderInitialSelectedDevice() throws {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(
                deviceID: "bluetooth-20-C1-9B-AA-BB-CC",
                displayName: "Magic Mouse",
                kind: .mouse,
                percent: nil,
                connectionState: .disconnected
            ),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18),
        ]

        let view = BeaconSettingsView(
            snapshots: snapshots,
            onRefresh: {},
            initialPane: .devices,
            initialSelectedDeviceID: "bluetooth-20-C1-9B-AA-BB-CC"
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-settings-selected-device-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testBeaconAlertsCanRenderInitialSelectedDeviceOverrides() throws {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18),
        ]

        let view = BeaconSettingsView(
            snapshots: snapshots,
            onRefresh: {},
            initialPane: .alerts,
            initialSelectedDeviceID: "watch"
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-alerts-selected-device-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testBeaconAlertsDetailPaneIsScrollable() throws {
        let view = BeaconSettingsView(
            snapshots: [
                makeDecorated(deviceID: "keyboard", displayName: "Keychron K3 Max", kind: .keyboard, percent: 35),
            ],
            notificationAuthorizationState: .authorized,
            onRefresh: {},
            initialPane: .alerts,
            initialSelectedDeviceID: "keyboard"
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(scrollViews(in: hostingView).count, 2)
    }

    @MainActor
    func testBeaconAlertsRenderNotificationCenterCardWithoutDevices() throws {
        let view = BeaconSettingsView(
            snapshots: [],
            notificationAuthorizationState: .denied,
            onRefresh: {},
            initialPane: .alerts
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-alerts-empty-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testDevicesAndAlertsSettingsSelectorColumnUsesSurfacedPanel() throws {
        withAppearanceTheme(.light) {
            let snapshots: [DecoratedBatterySnapshot] = [
                makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
                makeDecorated(deviceID: "mouse", displayName: "Magic Mouse", kind: .mouse, percent: 31),
                makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18),
            ]

            for pane in [SettingsPane.devices, .alerts] {
                let view = BeaconSettingsView(
                    snapshots: snapshots,
                    notificationAuthorizationState: .authorized,
                    onRefresh: {},
                    initialPane: pane,
                    initialSelectedDeviceID: "keyboard"
                )
                let hostingView = NSHostingView(rootView: view)
                hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
                hostingView.layoutSubtreeIfNeeded()

                let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
                XCTAssertNotNil(bitmap)

                guard let bitmap else { return }
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                let scale = backingScale(for: bitmap, in: hostingView)

                // Golden-layout guard for the 900x620 Settings render: these point ranges cover
                // the Devices/Alerts selector card, its former Divider strip, and the detail pane.
                let selectorColors = stride(from: 215, to: 485, by: 12).flatMap { x in
                    stride(from: 94, to: 530, by: 12).compactMap { y in
                        bitmap.colorAt(
                            x: pixelCoordinate(x, backingScale: scale),
                            y: pixelCoordinate(y, backingScale: scale)
                        )?.usingColorSpace(.deviceRGB)
                    }
                }
                let selectorEdgeColors = stride(from: 468, to: 486, by: 3).flatMap { x in
                    stride(from: 94, to: 530, by: 12).compactMap { y in
                        bitmap.colorAt(
                            x: pixelCoordinate(x, backingScale: scale),
                            y: pixelCoordinate(y, backingScale: scale)
                        )?.usingColorSpace(.deviceRGB)
                    }
                }
                let detailColors = stride(from: 510, to: 870, by: 16).flatMap { x in
                    stride(from: 94, to: 530, by: 16).compactMap { y in
                        bitmap.colorAt(
                            x: pixelCoordinate(x, backingScale: scale),
                            y: pixelCoordinate(y, backingScale: scale)
                        )?.usingColorSpace(.deviceRGB)
                    }
                }

                let visibleSelectorColors = selectorColors.filter { $0.alphaComponent > 0.05 }
                let uniqueSelectorEdgeColors = Set(selectorEdgeColors.map(roundedRGBAComponents))
                let uniqueDetailColors = Set(detailColors.map(roundedRGBAComponents))

                XCTAssertGreaterThan(visibleSelectorColors.count, 120)
                XCTAssertGreaterThan(uniqueSelectorEdgeColors.count, 1)
                XCTAssertGreaterThan(uniqueDetailColors.count, 12)
            }
        }
    }

    @MainActor
    func testSettingsEmptyStatesRenderSurfacedDetailCards() throws {
        try withAppearanceTheme(.light) {
            for pane in [SettingsPane.devices, .alerts] {
                let (hostingView, bitmap) = try renderedBitmap(
                    for: BeaconSettingsView(
                        snapshots: [],
                        notificationAuthorizationState: .authorized,
                        onRefresh: {},
                        initialPane: pane
                    ),
                    width: 900,
                    height: 620
                )
                let scale = backingScale(for: bitmap, in: hostingView)
                let cardAreaColors = sampledColors(
                    in: bitmap,
                    xValues: stride(from: 500, to: 880, by: 12),
                    yValues: stride(from: 80, to: 230, by: 12),
                    backingScale: scale
                )
                let visibleColors = cardAreaColors.filter { $0.alphaComponent > 0.05 }
                let uniqueVisibleColors = Set(visibleColors.map(roundedRGBAComponents))

                XCTAssertGreaterThan(visibleColors.count, 360)
                XCTAssertGreaterThan(
                    uniqueVisibleColors.count,
                    8,
                    "Expected the \(pane.title) empty detail area to render as a surfaced card, not plain text."
                )
            }
        }
    }

    @MainActor
    func testAddDeviceGuideRenderProducesNonBlankImage() throws {
        let view = AddDeviceGuideView(onOpenBluetoothSettings: {}, onDismiss: {})
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 330)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-add-device-guide-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 20_000)
    }

    @MainActor
    func testBatteryActionHUDRenderProducesNonBlankImage() throws {
        let view = BatteryActionHUDView(
            event: BatteryAlertEvent(
                kind: .lowBattery,
                deviceID: "watch",
                displayName: "Apple Watch",
                percent: 18
            )
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 92)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-action-hud-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 12_000)
    }

    @MainActor
    func testBeaconActionHUDSettingsRenderProducesNonBlankImage() throws {
        let view = BeaconSettingsView(
            snapshots: [
                makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18)
            ],
            onRefresh: {},
            initialPane: .actionHUD
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-action-hud-settings-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testBeaconQuickActionsSettingsRenderProducesNonBlankImage() throws {
        let view = BeaconSettingsView(
            snapshots: [],
            onRefresh: {},
            initialPane: .quickActions
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        XCTAssertNotNil(bitmap)

        guard let bitmap else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let outputURL = URL(fileURLWithPath: "/tmp/batteryhub-quick-actions-settings-render.png")
        let pngData = bitmap.representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)

        try pngData?.write(to: outputURL, options: .atomic)
        XCTAssertGreaterThan((pngData ?? Data()).count, 30_000)
    }

    @MainActor
    func testBeaconQuickActionsSettingsRenderShowsRightSideAutomationPanel() throws {
        withAppearanceTheme(.light) {
            withQuickActionPreferences(
                BeaconQuickActionPreferences(
                    enabledActionIDs: [
                        BeaconQuickAction.showDashboard.id,
                        BeaconQuickAction.refreshBatteries.id,
                        BeaconQuickAction.openSettings.id
                    ]
                )
            ) {
                let view = BeaconSettingsView(
                    snapshots: [],
                    onRefresh: {},
                    initialPane: .quickActions
                )
                let hostingView = NSHostingView(rootView: view)
                hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 620)
                hostingView.layoutSubtreeIfNeeded()

                let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
                XCTAssertNotNil(bitmap)

                guard let bitmap else { return }
                hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                let scale = backingScale(for: bitmap, in: hostingView)

                let panelColors = sampledColors(
                    in: bitmap,
                    xValues: stride(from: 590, to: 880, by: 12),
                    yValues: stride(from: 110, to: 520, by: 12),
                    backingScale: scale
                )
                let visibleColors = panelColors.filter { $0.alphaComponent > 0.05 }
                let uniqueColors = Set(visibleColors.map(roundedRGBAComponents))
                let rightEdgeColors = sampledColors(
                    in: bitmap,
                    xValues: stride(from: 852, to: 878, by: 4),
                    yValues: stride(from: 150, to: 500, by: 12),
                    backingScale: scale
                )
                let uniqueRightEdgeColors = Set(rightEdgeColors.map(roundedRGBAComponents))

                XCTAssertGreaterThan(visibleColors.count, 60)
                XCTAssertGreaterThan(uniqueColors.count, 12)
                XCTAssertGreaterThan(uniqueRightEdgeColors.count, 2)
            }
        }
    }

    @MainActor
    func testSettingsWindowClearsRefreshingStateAfterRefreshCompletes() async throws {
        let model = BeaconModel(environment: ["BEACON_PREVIEW_DATA": "1"])
        let statusController = BeaconStatusController(model: model)
        let settingsWindowController: BeaconSettingsWindowController = try XCTUnwrap(
            mirroredValue(in: statusController, label: "settingsWindowController")
        )

        settingsWindowController.showWindow()
        defer {
            let window: NSWindow? = mirroredValue(in: settingsWindowController, label: "window")
            window?.close()
        }

        XCTAssertFalse(try settingsRootView(in: settingsWindowController).isRefreshing)

        await model.refresh()

        XCTAssertFalse(try settingsRootView(in: settingsWindowController).isRefreshing)
    }

    @MainActor
    private func settingsRootView(in controller: BeaconSettingsWindowController) throws -> BeaconSettingsView {
        let hostingController: NSHostingController<BeaconSettingsView> = try XCTUnwrap(
            mirroredValue(in: controller, label: "hostingController")
        )
        return hostingController.rootView
    }

    private func mirroredValue<T>(in object: Any, label: String) -> T? {
        guard let value = Mirror(reflecting: object).children.first(where: { $0.label == label })?.value else {
            return nil
        }
        if let typedValue = value as? T {
            return typedValue
        }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first?.value as? T
        }
        return nil
    }
}

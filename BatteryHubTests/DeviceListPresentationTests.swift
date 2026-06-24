import AppKit
import AppIntents
import SwiftUI
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
        let suiteName = "BatteryHubTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

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
        let nativeOneDevice = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 1,
            showsOverview: false,
            visibleScreenHeight: 1_000
        )
        let nativeFiveDevices = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 5,
            showsOverview: false,
            visibleScreenHeight: 1_000
        )
        let oneDeviceWithOverview = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 1,
            showsOverview: true,
            visibleScreenHeight: 1_000
        )
        let fiveDevicesWithOverview = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 5,
            showsOverview: true,
            visibleScreenHeight: 1_000
        )

        XCTAssertEqual(nativeOneDevice.width, 386)
        XCTAssertGreaterThan(nativeOneDevice.height, 240)
        XCTAssertGreaterThan(nativeFiveDevices.height, nativeOneDevice.height)
        XCTAssertEqual(oneDeviceWithOverview.width, 386)
        XCTAssertEqual(oneDeviceWithOverview.height, nativeOneDevice.height)
        XCTAssertGreaterThan(fiveDevicesWithOverview.height, nativeFiveDevices.height)
        XCTAssertGreaterThan(fiveDevicesWithOverview.height, oneDeviceWithOverview.height)
        XCTAssertLessThan(fiveDevicesWithOverview.height, 560)
    }

    func testNativeStatusMenuSizingMatchesRenderedRowChrome() {
        let size = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 5,
            showsOverview: false,
            visibleScreenHeight: 1_000
        )

        XCTAssertEqual(size.width, 386)
        // Native widget-led chrome: 28 vertical padding + 58 header
        // + (18 list padding + 5 * 58 rows + 4 * 8 row gaps),
        // with settings moved into the header.
        XCTAssertEqual(size.height, 426)
    }

    func testStatusWindowConfigurationLoadsDashboardPreferences() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: StatusWindowPreferences.showMenuBarBatteryKey)
        defaults.set(false, forKey: StatusWindowPreferences.showBatteryOverviewKey)

        let configuration = StatusWindowConfiguration.load(from: defaults)

        XCTAssertTrue(configuration.showsMenuBarBattery)
        XCTAssertFalse(configuration.showsBatteryOverview)
    }

    func testStatusMenuSizingUsesNativeWidthWithoutLegacyCardHeight() {
        let withoutOverview = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 1,
            showsOverview: false,
            visibleScreenHeight: 1_000
        )
        let withOverview = StatusMenuSizing.preferredContentSize(
            dashboardItemCount: 1,
            showsOverview: true,
            visibleScreenHeight: 1_000
        )

        XCTAssertEqual(withoutOverview.width, 386)
        XCTAssertEqual(withOverview.width, 386)
        XCTAssertEqual(withOverview.height, withoutOverview.height)
        XCTAssertLessThan(withOverview.height, 560)
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
            showsOverview: true,
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
                AirPodsComponent(slot: .left, percent: 72, chargeState: .unplugged, freshness: .fresh, updatedAt: Self.fixedDate),
                AirPodsComponent(slot: .right, percent: 68, chargeState: .unplugged, freshness: .fresh, updatedAt: Self.fixedDate),
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
                AirPodsComponent(slot: .left, percent: 72, chargeState: .unplugged, freshness: .fresh, updatedAt: Self.fixedDate),
                AirPodsComponent(slot: .right, percent: 68, chargeState: .unplugged, freshness: .fresh, updatedAt: Self.fixedDate),
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
        XCTAssertEqual(DeviceContextMenuAction.remove.title(for: "AirPods Pro"), "Remove from BatteryHub")
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
        defaults.set(true, forKey: "BatteryHub.chargedBatteryAlerted.bluetooth-D1-B3-88-E2-67-CB")
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
        let success = NotificationCenterDeliveryResult.queued("BatteryHub Test Notification")
        let failure = NotificationCenterDeliveryResult.failed("Notifications are disabled")

        XCTAssertEqual(success.title, "Queued")
        XCTAssertEqual(success.subtitle, "BatteryHub Test Notification")
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
        XCTAssertTrue(BatteryHUDPreferences.showsDismissButton(defaults: defaults))
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
        let preferences = BatteryHubQuickActionPreferences()

        XCTAssertTrue(preferences.isEnabled(.showDashboard))
        XCTAssertTrue(preferences.isEnabled(.refreshBatteries))
        XCTAssertFalse(preferences.isEnabled(.openSettings))
        XCTAssertFalse(preferences.isEnabled(.addDevice))
        XCTAssertFalse(preferences.isEnabled(.openBluetoothSettings))
        XCTAssertFalse(preferences.isEnabled(.connectNearbyDevice))
        XCTAssertFalse(preferences.isEnabled(.disconnectLowestDevice))
        XCTAssertFalse(preferences.isEnabled(.transferToMac))
        XCTAssertEqual(BatteryHubQuickAction.showDashboard.shortcut?.displayText, "⌥⌘B")
        XCTAssertEqual(BatteryHubQuickAction.connectNearbyDevice.shortcut?.displayText, "⌥⌘N")
        XCTAssertEqual(BatteryHubQuickAction.disconnectLowestDevice.shortcut?.displayText, "⌥⌘X")
        XCTAssertNil(BatteryHubQuickAction.transferToMac.shortcut)
    }

    func testQuickActionPreferencesRoundTripAndFilterUnsupportedActions() {
        let defaults = isolatedDefaults()
        let preferences = BatteryHubQuickActionPreferences()
            .setting(false, for: .showDashboard)
            .setting(true, for: .openSettings)
            .setting(true, for: .connectNearbyDevice)
            .setting(true, for: .transferToMac)

        preferences.save(to: defaults)

        let restored = BatteryHubQuickActionPreferences.load(from: defaults)
        XCTAssertFalse(restored.isEnabled(.showDashboard))
        XCTAssertTrue(restored.isEnabled(.refreshBatteries))
        XCTAssertTrue(restored.isEnabled(.openSettings))
        XCTAssertTrue(restored.isEnabled(.connectNearbyDevice))
        XCTAssertFalse(restored.isEnabled(.transferToMac))
    }

    @MainActor
    func testBatteryHubAppShortcutsExposeSupportedAutomationActions() {
        let shortcutCount = BatteryHubAppShortcuts.appShortcuts.count

        XCTAssertEqual(shortcutCount, 10)
        XCTAssertNil(BatteryHubQuickAction.transferToMac.shortcut)
    }

    @MainActor
    func testBatteryHubIntentBridgeRunsSupportedActionsOnly() {
        var handledActions: [BatteryHubQuickAction] = []
        BatteryHubIntentBridge.shared.register(
            handler: { action in
                handledActions.append(action)
            },
            snapshotProvider: { [] }
        )

        XCTAssertTrue(BatteryHubIntentBridge.shared.perform(.refreshBatteries))
        XCTAssertFalse(BatteryHubIntentBridge.shared.perform(.transferToMac))
        XCTAssertEqual(handledActions, [.refreshBatteries])
    }

    @MainActor
    func testBatteryHubIntentBridgeProvidesSnapshotsForReadOnlyShortcuts() {
        let snapshots = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18),
        ]

        BatteryHubIntentBridge.shared.register(
            handler: { _ in },
            snapshotProvider: { snapshots }
        )

        XCTAssertEqual(BatteryHubIntentBridge.shared.snapshots(), snapshots)
    }

    func testBatteryHubShortcutSummaryFormatsUsefulAutomationText() {
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

        let summary = BatteryHubShortcutSnapshotFormatter.summary(
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
            "BatteryHub: 4 reporting devices. Lowest: Apple Watch 18%. Low battery: Apple Watch 18%. Charging: Isaac's iPhone 64%. Stale reports: 1."
        )
        XCTAssertEqual(
            BatteryHubShortcutSnapshotFormatter.lowBatteryText(
                for: snapshots,
                lowBatteryThreshold: 20
            ),
            "Apple Watch 18%"
        )
    }

    func testBatteryHubShortcutTrendSummaryUsesLocalHistory() {
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
            BatteryHubShortcutSnapshotFormatter.batteryTrendText(
                for: snapshots,
                defaults: defaults
            ),
            "Magic Keyboard: -5% trend, range 82%-87% across 2 reports."
        )
    }

    func testBatteryHubShortcutTrendSummaryFallsBackWhileCollecting() {
        XCTAssertEqual(
            BatteryHubShortcutSnapshotFormatter.batteryTrendText(
                for: [
                    makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82)
                ],
                defaults: isolatedDefaults()
            ),
            "No battery trends yet. BatteryHub builds trends as reports arrive."
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

    func testBatteryHubPrimarySymbolStaysSeparateFromBluetoothSymbol() {
        XCTAssertEqual(
            BatteryHubSymbols.app,
            resolveSymbol("rectangle.grid.2x2", fallback: "rectangle.grid.3x2")
        )
        XCTAssertNotEqual(BatteryHubSymbols.app, BatteryHubSymbols.bluetooth)
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

    func testMenuBarBatteryTextReturnsNilWhenNoFreshPercentExists() {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Keyboard", kind: .keyboard, percent: nil),
            makeDecorated(deviceID: "mouse", displayName: "Mouse", kind: .mouse, percent: 18, freshness: .expired),
        ]

        XCTAssertNil(MenuBarBatteryFormatter.menuBarText(for: snapshots))
    }

    func testMenuBarStatusIconUsesReadableMenuBarSizing() {
        XCTAssertEqual(BatteryHubStatusIconImage.designReferenceAssetName, BatteryHubSymbols.headerLogoAsset)
        XCTAssertEqual(BatteryHubMenuBarMetrics.iconSide, 24)
        XCTAssertEqual(BatteryHubMenuBarMetrics.imageOnlyLength, 32)

        let image = BatteryHubStatusIconImage.make()
        XCTAssertEqual(image.size.width, BatteryHubMenuBarMetrics.iconSide, accuracy: 0.01)
        XCTAssertEqual(image.size.height, BatteryHubMenuBarMetrics.iconSide, accuracy: 0.01)
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
        let controller = BatteryHubDesktopWidgetController()

        controller.update(
            snapshots: snapshots,
            isRefreshing: false,
            bluetoothPowerState: .on,
            onRefresh: {},
            onOpenSettings: {},
            onOpenBluetoothSettings: {}
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
            isRefreshing: false,
            bluetoothPowerState: .on,
            onRefresh: {},
            onOpenSettings: {},
            onOpenBluetoothSettings: {}
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
            bluetoothPowerState: .on,
            onRefresh: {},
            onOpenSettings: {},
            onOpenBluetoothSettings: {}
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
    func testBatteryHubDashboardSettingsRenderProducesDesktopWidgetPreview() throws {
        UserDefaults.standard.set(true, forKey: DesktopWidgetPreferences.showDesktopWidgetKey)
        UserDefaults.standard.set(DesktopWidgetStyle.expanded.rawValue, forKey: DesktopWidgetPreferences.widgetStyleKey)
        defer {
            UserDefaults.standard.removeObject(forKey: DesktopWidgetPreferences.showDesktopWidgetKey)
            UserDefaults.standard.removeObject(forKey: DesktopWidgetPreferences.widgetStyleKey)
        }

        let view = BatteryHubSettingsView(
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
            showsOverview: true,
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
        let previousTheme = UserDefaults.standard.string(forKey: BatteryHubAppearanceTheme.defaultsKey)
        UserDefaults.standard.set(BatteryHubAppearanceTheme.dark.rawValue, forKey: BatteryHubAppearanceTheme.defaultsKey)
        defer {
            if let previousTheme {
                UserDefaults.standard.set(previousTheme, forKey: BatteryHubAppearanceTheme.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: BatteryHubAppearanceTheme.defaultsKey)
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
            showsOverview: true,
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
        XCTAssertGreaterThan((pngData ?? Data()).count, 18_000)
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
    func testBatteryHubSettingsWindowRenderProducesNonBlankImage() throws {
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

        let view = BatteryHubSettingsView(snapshots: snapshots, onRefresh: {})
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
    func testBatteryHubSettingsWindowRefreshingRenderProducesNonBlankImage() throws {
        let view = BatteryHubSettingsView(
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
    func testBatteryHubSettingsWindowCanRenderAirPodsAudioControls() throws {
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

        let view = BatteryHubSettingsView(
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
    func testBatteryHubSettingsWindowCanRenderInitialSelectedDevice() throws {
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

        let view = BatteryHubSettingsView(
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
    func testBatteryHubAlertsCanRenderInitialSelectedDeviceOverrides() throws {
        let snapshots: [DecoratedBatterySnapshot] = [
            makeDecorated(deviceID: "keyboard", displayName: "Magic Keyboard", kind: .keyboard, percent: 82),
            makeDecorated(deviceID: "watch", displayName: "Apple Watch", kind: .appleWatch, percent: 18),
        ]

        let view = BatteryHubSettingsView(
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
    func testBatteryHubAlertsDetailPaneIsScrollable() throws {
        let view = BatteryHubSettingsView(
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
    func testBatteryHubAlertsRenderNotificationCenterCardWithoutDevices() throws {
        let view = BatteryHubSettingsView(
            snapshots: [],
            notificationAuthorizationState: .denied,
            latestNotificationDeliveryResult: .failed("Notifications are disabled"),
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
    func testBatteryHubActionHUDSettingsRenderProducesNonBlankImage() throws {
        let view = BatteryHubSettingsView(
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
    func testBatteryHubQuickActionsSettingsRenderProducesNonBlankImage() throws {
        let view = BatteryHubSettingsView(
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
}

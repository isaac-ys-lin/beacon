# Menu Bar Battery Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a polished personal-use macOS menu bar app that shows battery status for MacBook, iPhone, Apple Watch, Apple keyboard, and any connected Bluetooth devices that report battery data through public macOS or BLE surfaces.

**Architecture:** Use a native SwiftUI multi-target Apple project. The macOS app owns the menu bar UI, local MacBook battery reading, and local Bluetooth battery discovery. The iOS app reads iPhone battery and relays Apple Watch battery snapshots from the watchOS app, then publishes the latest snapshots through iCloud key-value storage for the Mac to consume.

**Tech Stack:** Swift 6, SwiftUI, AppKit, MenuBarExtra, IOKit, IOBluetooth, CoreBluetooth, UIKit, WatchKit, WatchConnectivity, iCloud KVS, XCTest.

---

## Design Direction

**Visual thesis:** Quiet precision utility: compact Apple-native surface, soft graphite neutrals, crisp tabular battery numbers, and restrained status color only where it communicates urgency.

**Content plan:** Orient with one menu bar summary. Show current device battery rows first. Group Bluetooth devices below with source and freshness states. Put settings and sync diagnostics in a small footer.

**Interaction thesis:** Rows reveal detail on hover or tap with a 120ms opacity and scale transition. Refresh uses a subtle icon cross-fade. Pressed controls scale to 0.96 and must honor reduced motion.

Benchmarks:
- AirBuddy: succeeds by making nearby device battery status feel glanceable and spatial, but this app should be denser and calmer because it lives primarily in the menu bar.
- Apple Control Center and Batteries widget: use familiar device glyphs, percentage labels, and charging state language, so this app should borrow the system vocabulary instead of inventing decorative metaphors.
- Raycast: keeps utility UI sharp through tight rows, clear keyboard-accessible actions, and minimal chrome, which is the right density model for the popover.

Design decisions:
- Typeface: use the macOS system font for UI text and SF Symbols for device glyphs. This is appropriate here because the product is an OS utility, not a branded marketing surface.
- Numbers: all battery percentages use tabular figures.
- Radius scale: `4px` for small chips, `8px` for rows, `12px` for the popover panel, `pill` for status chips.
- Color roles: neutral graphite surfaces, green for charging or healthy, amber for stale, red for critical, blue only for active sync.
- CSS strategy equivalent: no web CSS. Use SwiftUI tokens in `DesignTokens.swift` only, with no ad-hoc colors or radii inside views.

## Public Sources and Constraints

- macOS menu bar: Apple `MenuBarExtra`, https://developer.apple.com/documentation/swiftui/menubarextra
- Mac power sources: Apple `IOPowerSources`, https://developer.apple.com/documentation/iokit/iopowersources_h
- Bluetooth user-space access: Apple `IOBluetooth`, https://developer.apple.com/documentation/iobluetooth
- BLE service discovery: Apple `CBPeripheral.discoverServices`, https://developer.apple.com/documentation/corebluetooth/cbperipheral/discoverservices%28_%3A%29
- iPhone battery: Apple `UIDevice.batteryLevel`, https://developer.apple.com/documentation/uikit/uidevice/batterylevel
- Apple Watch battery: Apple `WKInterfaceDevice.batteryLevel`, https://developer.apple.com/documentation/watchkit/wkinterfacedevice/batterylevel
- Watch to iPhone sync: Apple `WatchConnectivity`, https://developer.apple.com/documentation/watchconnectivity

Product constraints:
- Use public APIs only.
- Do not scrape private Apple databases.
- Do not use private frameworks.
- Do not promise real-time iPhone or Apple Watch battery status. Show last-known data with freshness.
- Bluetooth battery is best-effort. Only display a percentage when the connected device reports one through a supported provider.

## File Structure

Create:
- `BatteryHub.xcodeproj`
- `BatteryHub/Shared/BatterySnapshot.swift`: shared device, status, source, and freshness models.
- `BatteryHub/Shared/BatterySnapshotStore.swift`: in-memory merge and stale-state logic.
- `BatteryHub/Shared/CloudBatterySync.swift`: iCloud KVS publisher and subscriber for iOS and macOS.
- `BatteryHub/Shared/DesignTokens.swift`: SwiftUI color, radius, spacing, and motion constants.
- `BatteryHub/Mac/BatteryHubMacApp.swift`: macOS app entrypoint and MenuBarExtra.
- `BatteryHub/Mac/StatusMenuView.swift`: polished popover UI.
- `BatteryHub/Mac/DeviceBatteryRow.swift`: reusable device row.
- `BatteryHub/Mac/MacPowerSourceReader.swift`: MacBook battery reader.
- `BatteryHub/Mac/BluetoothBatteryResolver.swift`: multi-provider Bluetooth battery reader.
- `BatteryHub/Mac/BluetoothDeviceScanner.swift`: connected device enumeration and BLE Battery Service discovery.
- `BatteryHub/iOS/BatteryHubiOSApp.swift`: iOS companion entrypoint.
- `BatteryHub/iOS/iPhoneBatteryReporter.swift`: iPhone battery reader and publisher.
- `BatteryHub/iOS/WatchBatteryRelay.swift`: WatchConnectivity receiver.
- `BatteryHub/Watch/BatteryHubWatchApp.swift`: watchOS companion entrypoint.
- `BatteryHub/Watch/WatchBatteryReporter.swift`: Apple Watch battery reader and WatchConnectivity sender.
- `BatteryHubTests/BatterySnapshotStoreTests.swift`
- `BatteryHubTests/CloudBatterySyncTests.swift`
- `BatteryHubTests/BluetoothBatteryResolverTests.swift`
- `BatteryHubUITests/StatusMenuSnapshotTests.swift`

Modify after Xcode scaffolding:
- `BatteryHub/Mac/Info.plist`: set `LSUIElement` to `YES`.
- macOS entitlements: enable iCloud KVS and Bluetooth access as required by the final Xcode target settings.
- iOS entitlements: enable iCloud KVS.
- watchOS entitlements: enable WatchConnectivity pairing with the companion iOS app.

## Task 1: Scaffold the Apple Project

**Files:**
- Create: `BatteryHub.xcodeproj`
- Create: `BatteryHub/`
- Create: `BatteryHubTests/`
- Create: `BatteryHubUITests/`

- [ ] **Step 1: Create the Xcode project**

Use Xcode:
```text
File > New > Project
Platform: Multiplatform
Template: App
Product Name: BatteryHub
Organization Identifier: com.isaacyslin
Interface: SwiftUI
Language: Swift
Include Tests: Yes
```

- [ ] **Step 2: Add targets**

In Xcode, add:
```text
macOS App target: BatteryHubMac
iOS App target: BatteryHubiOS
watchOS App target: BatteryHubWatch
Unit Test target: BatteryHubTests
UI Test target: BatteryHubUITests
```

- [ ] **Step 3: Configure signing**

Set all targets to the same Apple Developer Team.

Bundle identifiers:
```text
com.isaacyslin.BatteryHub.mac
com.isaacyslin.BatteryHub.ios
com.isaacyslin.BatteryHub.watch
```

- [ ] **Step 4: Configure capabilities**

Enable:
```text
BatteryHubMac: iCloud Key-value storage, Bluetooth
BatteryHubiOS: iCloud Key-value storage
BatteryHubWatch: Watch Connectivity
```

- [ ] **Step 5: Hide the Mac app from Dock**

Add this key to the macOS target Info.plist:
```xml
<key>LSUIElement</key>
<true/>
```

- [ ] **Step 6: Build the empty targets**

Run:
```bash
xcodebuild -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' build
```

Expected: build succeeds with exit code 0.

- [ ] **Step 7: Commit**

```bash
git add BatteryHub.xcodeproj BatteryHub BatteryHubTests BatteryHubUITests
git commit -m "chore: scaffold battery hub apple targets"
```

## Task 2: Add Shared Battery Models

**Files:**
- Create: `BatteryHub/Shared/BatterySnapshot.swift`
- Create: `BatteryHub/Shared/BatterySnapshotStore.swift`
- Test: `BatteryHubTests/BatterySnapshotStoreTests.swift`

- [ ] **Step 1: Write model tests**

Create `BatteryHubTests/BatterySnapshotStoreTests.swift`:
```swift
import XCTest
@testable import BatteryHub

final class BatterySnapshotStoreTests: XCTestCase {
    func testMergeKeepsNewestSnapshotPerDevice() {
        let old = BatterySnapshot(
            deviceID: "iphone",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 42,
            chargeState: .unplugged,
            source: .iCloud,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let new = BatterySnapshot(
            deviceID: "iphone",
            displayName: "Isaac's iPhone",
            kind: .iPhone,
            percent: 43,
            chargeState: .charging,
            source: .iCloud,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 300) })
        store.merge([old])
        store.merge([new])

        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots[0].percent, 43)
        XCTAssertEqual(store.snapshots[0].chargeState, .charging)
    }

    func testFreshnessBucketsUseConfiguredThresholds() {
        let snapshot = BatterySnapshot(
            deviceID: "watch",
            displayName: "Apple Watch",
            kind: .appleWatch,
            percent: 88,
            chargeState: .unplugged,
            source: .watchConnectivity,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 700) })
        store.merge([snapshot])

        XCTAssertEqual(store.decoratedSnapshots[0].freshness, .stale)
    }

    func testUnsupportedBluetoothDeviceStaysVisibleWithoutPercent() {
        let snapshot = BatterySnapshot(
            deviceID: "bt-keyboard",
            displayName: "Keychron K2",
            kind: .bluetoothPeripheral,
            percent: nil,
            chargeState: .unknown,
            source: .bluetoothUnsupported,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var store = BatterySnapshotStore(now: { Date(timeIntervalSince1970: 120) })
        store.merge([snapshot])

        XCTAssertNil(store.snapshots[0].percent)
        XCTAssertEqual(store.snapshots[0].source, .bluetoothUnsupported)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/BatterySnapshotStoreTests
```

Expected: FAIL because `BatterySnapshot` and `BatterySnapshotStore` do not exist.

- [ ] **Step 3: Implement shared models**

Create `BatteryHub/Shared/BatterySnapshot.swift`:
```swift
import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case macBook
    case iPhone
    case appleWatch
    case keyboard
    case bluetoothPeripheral
}

public enum ChargeState: String, Codable, Sendable {
    case unknown
    case unplugged
    case charging
    case full
}

public enum BatterySource: String, Codable, Sendable {
    case macPowerSource
    case iCloud
    case watchConnectivity
    case ioRegistry
    case coreBluetooth
    case ioBluetooth
    case bluetoothUnsupported
}

public enum Freshness: String, Codable, Sendable {
    case fresh
    case stale
    case expired
}

public struct BatterySnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String { deviceID }
    public let deviceID: String
    public let displayName: String
    public let kind: DeviceKind
    public let percent: Int?
    public let chargeState: ChargeState
    public let source: BatterySource
    public let updatedAt: Date

    public init(
        deviceID: String,
        displayName: String,
        kind: DeviceKind,
        percent: Int?,
        chargeState: ChargeState,
        source: BatterySource,
        updatedAt: Date
    ) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.kind = kind
        self.percent = percent
        self.chargeState = chargeState
        self.source = source
        self.updatedAt = updatedAt
    }
}

public struct DecoratedBatterySnapshot: Equatable, Identifiable, Sendable {
    public var id: String { snapshot.id }
    public let snapshot: BatterySnapshot
    public let freshness: Freshness
}
```

Create `BatteryHub/Shared/BatterySnapshotStore.swift`:
```swift
import Foundation

public struct BatterySnapshotStore: Sendable {
    private var snapshotsByID: [String: BatterySnapshot] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public var snapshots: [BatterySnapshot] {
        snapshotsByID.values.sorted { left, right in
            if left.kind.sortOrder != right.kind.sortOrder {
                return left.kind.sortOrder < right.kind.sortOrder
            }
            return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
        }
    }

    public var decoratedSnapshots: [DecoratedBatterySnapshot] {
        snapshots.map { snapshot in
            DecoratedBatterySnapshot(
                snapshot: snapshot,
                freshness: Self.freshness(for: snapshot, now: now())
            )
        }
    }

    public mutating func merge(_ incoming: [BatterySnapshot]) {
        for snapshot in incoming {
            if let existing = snapshotsByID[snapshot.deviceID], existing.updatedAt > snapshot.updatedAt {
                continue
            }
            snapshotsByID[snapshot.deviceID] = snapshot
        }
    }

    public static func freshness(for snapshot: BatterySnapshot, now: Date) -> Freshness {
        let age = now.timeIntervalSince(snapshot.updatedAt)
        if age >= 1_800 { return .expired }
        if age >= 600 { return .stale }
        return .fresh
    }
}

private extension DeviceKind {
    var sortOrder: Int {
        switch self {
        case .macBook: return 0
        case .iPhone: return 1
        case .appleWatch: return 2
        case .keyboard: return 3
        case .bluetoothPeripheral: return 4
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/BatterySnapshotStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BatteryHub/Shared BatteryHubTests/BatterySnapshotStoreTests.swift
git commit -m "feat: add shared battery snapshot model"
```

## Task 3: Add MacBook Battery Reader

**Files:**
- Create: `BatteryHub/Mac/MacPowerSourceReader.swift`
- Test: `BatteryHubTests/MacPowerSourceReaderTests.swift`

- [ ] **Step 1: Write parser test**

Create `BatteryHubTests/MacPowerSourceReaderTests.swift`:
```swift
import XCTest
@testable import BatteryHub

final class MacPowerSourceReaderTests: XCTestCase {
    func testSnapshotFromPowerSourceDictionary() {
        let dictionary: [String: Any] = [
            "Name": "InternalBattery-0",
            "Current Capacity": 81,
            "Max Capacity": 100,
            "Is Charging": true
        ]

        let snapshot = MacPowerSourceReader.snapshot(from: dictionary, now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(snapshot?.kind, .macBook)
        XCTAssertEqual(snapshot?.percent, 81)
        XCTAssertEqual(snapshot?.chargeState, .charging)
        XCTAssertEqual(snapshot?.source, .macPowerSource)
    }
}
```

- [ ] **Step 2: Verify test fails**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/MacPowerSourceReaderTests
```

Expected: FAIL because `MacPowerSourceReader` does not exist.

- [ ] **Step 3: Implement reader**

Create `BatteryHub/Mac/MacPowerSourceReader.swift`:
```swift
import Foundation
import IOKit.ps

public struct MacPowerSourceReader {
    public init() {}

    public func read(now: Date = Date()) -> [BatterySnapshot] {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return []
        }

        return sources.compactMap { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                return nil
            }
            return Self.snapshot(from: description, now: now)
        }
    }

    static func snapshot(from description: [String: Any], now: Date) -> BatterySnapshot? {
        guard
            let current = description[kIOPSCurrentCapacityKey as String] as? Int,
            let max = description[kIOPSMaxCapacityKey as String] as? Int,
            max > 0
        else {
            return nil
        }

        let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) == true
        let percent = max(0, min(100, Int((Double(current) / Double(max) * 100).rounded())))

        return BatterySnapshot(
            deviceID: "macbook",
            displayName: "MacBook",
            kind: .macBook,
            percent: percent,
            chargeState: isCharging ? .charging : .unplugged,
            source: .macPowerSource,
            updatedAt: now
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/MacPowerSourceReaderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BatteryHub/Mac/MacPowerSourceReader.swift BatteryHubTests/MacPowerSourceReaderTests.swift
git commit -m "feat: read macbook battery state"
```

## Task 4: Add Bluetooth Battery Resolver

**Files:**
- Create: `BatteryHub/Mac/BluetoothBatteryResolver.swift`
- Create: `BatteryHub/Mac/BluetoothDeviceScanner.swift`
- Test: `BatteryHubTests/BluetoothBatteryResolverTests.swift`

- [ ] **Step 1: Write resolver tests**

Create `BatteryHubTests/BluetoothBatteryResolverTests.swift`:
```swift
import XCTest
@testable import BatteryHub

final class BluetoothBatteryResolverTests: XCTestCase {
    func testIORegistryBatteryPercentCreatesKeyboardSnapshot() {
        let device = BluetoothBatteryCandidate(
            deviceID: "apple-keyboard",
            displayName: "Magic Keyboard",
            transport: .hid,
            batteryPercent: 64
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.displayName, "Magic Keyboard")
        XCTAssertEqual(snapshot.kind, .keyboard)
        XCTAssertEqual(snapshot.percent, 64)
        XCTAssertEqual(snapshot.source, .ioRegistry)
    }

    func testDeviceWithoutBatteryIsVisibleAsUnsupported() {
        let device = BluetoothBatteryCandidate(
            deviceID: "speaker",
            displayName: "Kitchen Speaker",
            transport: .unknown,
            batteryPercent: nil
        )

        let snapshot = BluetoothBatteryResolver.snapshot(from: device, now: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(snapshot.percent, nil)
        XCTAssertEqual(snapshot.source, .bluetoothUnsupported)
    }
}
```

- [ ] **Step 2: Verify tests fail**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/BluetoothBatteryResolverTests
```

Expected: FAIL because Bluetooth resolver types do not exist.

- [ ] **Step 3: Implement resolver**

Create `BatteryHub/Mac/BluetoothBatteryResolver.swift`:
```swift
import Foundation

public enum BluetoothTransport: Sendable {
    case hid
    case ble
    case classic
    case unknown
}

public struct BluetoothBatteryCandidate: Sendable {
    public let deviceID: String
    public let displayName: String
    public let transport: BluetoothTransport
    public let batteryPercent: Int?

    public init(deviceID: String, displayName: String, transport: BluetoothTransport, batteryPercent: Int?) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.transport = transport
        self.batteryPercent = batteryPercent
    }
}

public struct BluetoothBatteryResolver {
    public init() {}

    public func read(now: Date = Date()) -> [BatterySnapshot] {
        BluetoothDeviceScanner().connectedCandidates().map {
            Self.snapshot(from: $0, now: now)
        }
    }

    static func snapshot(from candidate: BluetoothBatteryCandidate, now: Date) -> BatterySnapshot {
        let percent = candidate.batteryPercent.map { max(0, min(100, $0)) }
        let isKeyboard = candidate.displayName.localizedCaseInsensitiveContains("keyboard")

        return BatterySnapshot(
            deviceID: "bluetooth-\(candidate.deviceID)",
            displayName: candidate.displayName,
            kind: isKeyboard ? .keyboard : .bluetoothPeripheral,
            percent: percent,
            chargeState: .unknown,
            source: source(for: candidate),
            updatedAt: now
        )
    }

    private static func source(for candidate: BluetoothBatteryCandidate) -> BatterySource {
        if candidate.batteryPercent == nil { return .bluetoothUnsupported }
        switch candidate.transport {
        case .hid: return .ioRegistry
        case .ble: return .coreBluetooth
        case .classic: return .ioBluetooth
        case .unknown: return .bluetoothUnsupported
        }
    }
}
```

- [ ] **Step 4: Implement scanner shell with safe fallbacks**

Create `BatteryHub/Mac/BluetoothDeviceScanner.swift`:
```swift
import Foundation
import IOBluetooth
import IOKit

public struct BluetoothDeviceScanner {
    public init() {}

    public func connectedCandidates() -> [BluetoothBatteryCandidate] {
        let hid = readHIDBatteryCandidates()
        let knownIDs = Set(hid.map(\.deviceID))
        let classic = readConnectedIOBluetoothDevices().filter { !knownIDs.contains($0.deviceID) }
        return hid + classic
    }

    private func readConnectedIOBluetoothDevices() -> [BluetoothBatteryCandidate] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return devices.compactMap { device in
            guard device.isConnected() else { return nil }
            let address = device.addressString ?? device.nameOrAddress
            let name = device.nameOrAddress
            return BluetoothBatteryCandidate(
                deviceID: address,
                displayName: name,
                transport: .classic,
                batteryPercent: nil
            )
        }
    }

    private func readHIDBatteryCandidates() -> [BluetoothBatteryCandidate] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [BluetoothBatteryCandidate] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let name = property("Product", service: service) ?? property("ProductID", service: service) ?? "Bluetooth Device"
            let id = property("SerialNumber", service: service) ?? name
            let percent = intProperty("BatteryPercent", service: service)

            if percent != nil || name.localizedCaseInsensitiveContains("keyboard") {
                results.append(
                    BluetoothBatteryCandidate(
                        deviceID: id,
                        displayName: name,
                        transport: .hid,
                        batteryPercent: percent
                    )
                )
            }
        }
        return results
    }

    private func property(_ key: String, service: io_object_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return value as? String
    }

    private func intProperty(_ key: String, service: io_object_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }
}
```

- [ ] **Step 5: Run resolver tests**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/BluetoothBatteryResolverTests
```

Expected: PASS.

- [ ] **Step 6: Manual Bluetooth acceptance check**

Run the Mac app on a machine with one Apple keyboard and at least one non-keyboard Bluetooth device connected.

Expected:
```text
Magic Keyboard: shows percent when macOS reports BatteryPercent
Connected device without battery report: shows "No battery report"
No duplicate rows for the same HID device
```

- [ ] **Step 7: Commit**

```bash
git add BatteryHub/Mac/BluetoothBatteryResolver.swift BatteryHub/Mac/BluetoothDeviceScanner.swift BatteryHubTests/BluetoothBatteryResolverTests.swift
git commit -m "feat: resolve bluetooth battery snapshots"
```

## Task 5: Add iCloud Battery Sync

**Files:**
- Create: `BatteryHub/Shared/CloudBatterySync.swift`
- Test: `BatteryHubTests/CloudBatterySyncTests.swift`

- [ ] **Step 1: Write encode/decode tests**

Create `BatteryHubTests/CloudBatterySyncTests.swift`:
```swift
import XCTest
@testable import BatteryHub

final class CloudBatterySyncTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let envelope = SyncEnvelope(
            schemaVersion: 1,
            snapshots: [
                BatterySnapshot(
                    deviceID: "iphone",
                    displayName: "Isaac's iPhone",
                    kind: .iPhone,
                    percent: 75,
                    chargeState: .charging,
                    source: .iCloud,
                    updatedAt: Date(timeIntervalSince1970: 123)
                )
            ],
            publishedAt: Date(timeIntervalSince1970: 456)
        )

        let data = try JSONEncoder.batteryHub.encode(envelope)
        let decoded = try JSONDecoder.batteryHub.decode(SyncEnvelope.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.snapshots[0].percent, 75)
        XCTAssertEqual(decoded.publishedAt, Date(timeIntervalSince1970: 456))
    }
}
```

- [ ] **Step 2: Verify test fails**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/CloudBatterySyncTests
```

Expected: FAIL because `SyncEnvelope` and coders do not exist.

- [ ] **Step 3: Implement sync envelope**

Create `BatteryHub/Shared/CloudBatterySync.swift`:
```swift
import Foundation

public struct SyncEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let snapshots: [BatterySnapshot]
    public let publishedAt: Date

    public init(schemaVersion: Int = 1, snapshots: [BatterySnapshot], publishedAt: Date = Date()) {
        self.schemaVersion = schemaVersion
        self.snapshots = snapshots
        self.publishedAt = publishedAt
    }
}

public extension JSONEncoder {
    static var batteryHub: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var batteryHub: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public final class CloudBatterySync {
    public static let storageKey = "BatteryHub.SyncEnvelope.v1"
    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func publish(_ snapshots: [BatterySnapshot], now: Date = Date()) throws {
        let envelope = SyncEnvelope(snapshots: snapshots, publishedAt: now)
        let data = try JSONEncoder.batteryHub.encode(envelope)
        store.set(data, forKey: Self.storageKey)
        store.synchronize()
    }

    public func load() throws -> SyncEnvelope? {
        guard let data = store.data(forKey: Self.storageKey) else {
            return nil
        }
        return try JSONDecoder.batteryHub.decode(SyncEnvelope.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubTests/CloudBatterySyncTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BatteryHub/Shared/CloudBatterySync.swift BatteryHubTests/CloudBatterySyncTests.swift
git commit -m "feat: add icloud battery sync envelope"
```

## Task 6: Add iPhone and Watch Reporters

**Files:**
- Create: `BatteryHub/iOS/iPhoneBatteryReporter.swift`
- Create: `BatteryHub/iOS/WatchBatteryRelay.swift`
- Create: `BatteryHub/Watch/WatchBatteryReporter.swift`

- [ ] **Step 1: Implement iPhone battery reporter**

Create `BatteryHub/iOS/iPhoneBatteryReporter.swift`:
```swift
import Foundation
import UIKit

public final class iPhoneBatteryReporter {
    private let sync: CloudBatterySync

    public init(sync: CloudBatterySync = CloudBatterySync()) {
        self.sync = sync
    }

    public func publishCurrentBattery(now: Date = Date(), watchSnapshots: [BatterySnapshot] = []) throws {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let percent = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : nil

        let snapshot = BatterySnapshot(
            deviceID: "iphone",
            displayName: UIDevice.current.name,
            kind: .iPhone,
            percent: percent,
            chargeState: Self.chargeState(from: UIDevice.current.batteryState),
            source: .iCloud,
            updatedAt: now
        )

        try sync.publish([snapshot] + watchSnapshots, now: now)
    }

    private static func chargeState(from state: UIDevice.BatteryState) -> ChargeState {
        switch state {
        case .unknown: return .unknown
        case .unplugged: return .unplugged
        case .charging: return .charging
        case .full: return .full
        @unknown default: return .unknown
        }
    }
}
```

- [ ] **Step 2: Implement WatchConnectivity relay**

Create `BatteryHub/iOS/WatchBatteryRelay.swift`:
```swift
import Foundation
import WatchConnectivity

public final class WatchBatteryRelay: NSObject, WCSessionDelegate {
    private let reporter: iPhoneBatteryReporter
    private var latestWatchSnapshots: [BatterySnapshot] = []

    public init(reporter: iPhoneBatteryReporter = iPhoneBatteryReporter()) {
        self.reporter = reporter
        super.init()
    }

    public func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard
            let data = userInfo["snapshot"] as? Data,
            let snapshot = try? JSONDecoder.batteryHub.decode(BatterySnapshot.self, from: data)
        else {
            return
        }
        latestWatchSnapshots = [snapshot]
        try? reporter.publishCurrentBattery(watchSnapshots: latestWatchSnapshots)
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
```

- [ ] **Step 3: Implement watch battery reporter**

Create `BatteryHub/Watch/WatchBatteryReporter.swift`:
```swift
import Foundation
import WatchConnectivity
import WatchKit

public final class WatchBatteryReporter: NSObject, WCSessionDelegate {
    public override init() {
        super.init()
    }

    public func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public func sendCurrentBattery(now: Date = Date()) {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let rawLevel = WKInterfaceDevice.current().batteryLevel
        let percent = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : nil

        let snapshot = BatterySnapshot(
            deviceID: "apple-watch",
            displayName: WKInterfaceDevice.current().name,
            kind: .appleWatch,
            percent: percent,
            chargeState: chargeState(from: WKInterfaceDevice.current().batteryState),
            source: .watchConnectivity,
            updatedAt: now
        )

        guard let data = try? JSONEncoder.batteryHub.encode(snapshot) else {
            return
        }
        WCSession.default.transferUserInfo(["snapshot": data])
    }

    private func chargeState(from state: WKInterfaceDeviceBatteryState) -> ChargeState {
        switch state {
        case .unknown: return .unknown
        case .unplugged: return .unplugged
        case .charging: return .charging
        case .full: return .full
        @unknown default: return .unknown
        }
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}
}
```

- [ ] **Step 4: Wire reporters into app entrypoints**

In the iOS app entrypoint, create one `WatchBatteryRelay`, call `start()` at launch, and call `iPhoneBatteryReporter.publishCurrentBattery()` on app foreground.

In the watchOS app entrypoint, create one `WatchBatteryReporter`, call `start()` at launch, and call `sendCurrentBattery()` on app foreground.

- [ ] **Step 5: Build iOS and watchOS targets**

Run:
```bash
xcodebuild -project BatteryHub.xcodeproj -scheme BatteryHubiOS -destination 'generic/platform=iOS' build
xcodebuild -project BatteryHub.xcodeproj -scheme BatteryHubWatch -destination 'generic/platform=watchOS' build
```

Expected: both builds succeed.

- [ ] **Step 6: Physical-device acceptance check**

Install iOS and watchOS apps on paired physical devices.

Expected:
```text
iPhone app foreground: Mac receives iPhone battery through iCloud KVS.
Watch app foreground: iPhone receives watch snapshot through WatchConnectivity.
Mac popover: iPhone and Apple Watch rows show percent plus last updated timestamp.
```

- [ ] **Step 7: Commit**

```bash
git add BatteryHub/iOS BatteryHub/Watch
git commit -m "feat: sync iphone and apple watch battery snapshots"
```

## Task 7: Build the Elegant Menu Bar UI

**Files:**
- Create: `BatteryHub/Shared/DesignTokens.swift`
- Create: `BatteryHub/Mac/BatteryHubMacApp.swift`
- Create: `BatteryHub/Mac/StatusMenuView.swift`
- Create: `BatteryHub/Mac/DeviceBatteryRow.swift`
- Test: `BatteryHubUITests/StatusMenuSnapshotTests.swift`

- [ ] **Step 1: Implement design tokens**

Create `BatteryHub/Shared/DesignTokens.swift`:
```swift
import SwiftUI

public enum DesignTokens {
    public enum Radius {
        public static let chip: CGFloat = 4
        public static let row: CGFloat = 8
        public static let panel: CGFloat = 12
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
    }

    public enum Motion {
        public static let quick: Double = 0.12
    }

    public enum Palette {
        public static let panel = Color(nsColor: .windowBackgroundColor)
        public static let row = Color(nsColor: .controlBackgroundColor)
        public static let text = Color.primary
        public static let secondaryText = Color.secondary
        public static let charging = Color.green
        public static let stale = Color.orange
        public static let critical = Color.red
        public static let sync = Color.blue
    }
}
```

- [ ] **Step 2: Implement row view**

Create `BatteryHub/Mac/DeviceBatteryRow.swift`:
```swift
import SwiftUI

struct DeviceBatteryRow: View {
    let decorated: DecoratedBatterySnapshot

    var body: some View {
        let snapshot = decorated.snapshot

        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: symbolName(for: snapshot.kind))
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            Text(percentText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(percentColor)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 10)
        .background(DesignTokens.Palette.row, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.row))
    }

    private var percentText: String {
        guard let percent = decorated.snapshot.percent else { return "--" }
        return "\(percent)%"
    }

    private var statusText: String {
        if decorated.snapshot.percent == nil {
            return "No battery report"
        }
        switch decorated.freshness {
        case .fresh: return decorated.snapshot.chargeState == .charging ? "Charging" : "Updated recently"
        case .stale: return "Last updated over 10 min ago"
        case .expired: return "Last updated over 30 min ago"
        }
    }

    private var iconColor: Color {
        switch decorated.snapshot.chargeState {
        case .charging, .full: return DesignTokens.Palette.charging
        default: return DesignTokens.Palette.secondaryText
        }
    }

    private var percentColor: Color {
        guard let percent = decorated.snapshot.percent else { return DesignTokens.Palette.secondaryText }
        if percent <= 15 { return DesignTokens.Palette.critical }
        if decorated.freshness != .fresh { return DesignTokens.Palette.stale }
        return DesignTokens.Palette.text
    }

    private func symbolName(for kind: DeviceKind) -> String {
        switch kind {
        case .macBook: return "macbook"
        case .iPhone: return "iphone"
        case .appleWatch: return "applewatch"
        case .keyboard: return "keyboard"
        case .bluetoothPeripheral: return "dot.radiowaves.left.and.right"
        }
    }
}
```

- [ ] **Step 3: Implement status popover**

Create `BatteryHub/Mac/StatusMenuView.swift`:
```swift
import SwiftUI

struct StatusMenuView: View {
    let snapshots: [DecoratedBatterySnapshot]
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            header

            VStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(snapshots) { decorated in
                    DeviceBatteryRow(decorated: decorated)
                }
            }

            footer
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 340)
        .background(DesignTokens.Palette.panel)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("BatteryHub")
                    .font(.system(size: 15, weight: .semibold))
                Text("Devices at a glance")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Refresh")
        }
    }

    private var footer: some View {
        HStack {
            Text("Best-effort sync")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Spacer()
            Button("Settings") {}
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
        }
    }
}
```

- [ ] **Step 4: Implement macOS entrypoint**

Create `BatteryHub/Mac/BatteryHubMacApp.swift`:
```swift
import SwiftUI

@main
struct BatteryHubMacApp: App {
    @State private var store = BatterySnapshotStore()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(
                snapshots: store.decoratedSnapshots,
                onRefresh: refresh
            )
        } label: {
            Label(summaryText, systemImage: "battery.75percent")
        }
        .menuBarExtraStyle(.window)
    }

    private var summaryText: String {
        let percents = store.snapshots.compactMap(\.percent)
        guard let lowest = percents.min() else { return "BatteryHub" }
        return "\(lowest)%"
    }

    private func refresh() {
        var nextStore = store
        nextStore.merge(MacPowerSourceReader().read())
        nextStore.merge(BluetoothBatteryResolver().read())
        if let envelope = try? CloudBatterySync().load() {
            nextStore.merge(envelope.snapshots)
        }
        store = nextStore
    }
}
```

- [ ] **Step 5: Add UI snapshot smoke test**

Create `BatteryHubUITests/StatusMenuSnapshotTests.swift`:
```swift
import XCTest

final class StatusMenuSnapshotTests: XCTestCase {
    func testMenuBarAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists)
    }
}
```

- [ ] **Step 6: Run macOS build and UI test**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS' -only-testing:BatteryHubUITests/StatusMenuSnapshotTests
```

Expected: PASS.

- [ ] **Step 7: Manual visual acceptance check**

Open the app and click the menu bar item.

Expected:
```text
Panel width is 340 pt.
Rows do not wrap with device names up to 28 visible characters.
Percent labels align vertically with tabular numbers.
Unsupported Bluetooth devices show "--" and "No battery report".
Stale iPhone or Apple Watch data uses amber text and explicit last-known copy.
The UI does not use large marketing headers, generic cards, purple-blue gradients, or decorative blobs.
```

- [ ] **Step 8: Commit**

```bash
git add BatteryHub/Shared/DesignTokens.swift BatteryHub/Mac BatteryHubUITests/StatusMenuSnapshotTests.swift
git commit -m "feat: add polished menu bar battery ui"
```

## Task 8: Final Verification

**Files:**
- Modify: no source files unless verification exposes a failing check.

- [ ] **Step 1: Run all unit tests**

Run:
```bash
xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 2: Run iOS build**

Run:
```bash
xcodebuild -project BatteryHub.xcodeproj -scheme BatteryHubiOS -destination 'generic/platform=iOS' build
```

Expected: PASS.

- [ ] **Step 3: Run watchOS build**

Run:
```bash
xcodebuild -project BatteryHub.xcodeproj -scheme BatteryHubWatch -destination 'generic/platform=watchOS' build
```

Expected: PASS.

- [ ] **Step 4: Run physical-device sync check**

Use paired iPhone and Apple Watch.

Expected:
```text
MacBook row updates from local Mac state.
Bluetooth rows appear for connected devices.
Keyboard row shows a percent when macOS reports BatteryPercent.
iPhone row appears after iPhone companion runs.
Apple Watch row appears after watch companion runs and iPhone relays it.
Rows older than 10 minutes show stale state.
Rows older than 30 minutes show expired state.
```

- [ ] **Step 5: Run final visual check**

Inspect the menu at normal and compact menu bar widths.

Expected:
```text
No clipped labels.
No overlapping rows.
All clickable controls are at least 40 pt hit area or have expanded contentShape.
Refresh button has a help tooltip.
Panel still reads as a utility, not a landing page.
```

- [ ] **Step 6: Commit verification fixes**

If Step 1 through Step 5 required fixes:
```bash
git add BatteryHub BatteryHubTests BatteryHubUITests
git commit -m "fix: polish battery hub verification issues"
```

If no fixes were required, do not create an empty commit.

## Risks and Rollback

- Bluetooth battery reporting is device-dependent. Rollback is to keep Bluetooth rows visible but mark unsupported devices as `No battery report`.
- iPhone and Apple Watch background freshness is best-effort. Rollback is to lengthen stale thresholds or require manual refresh from companion apps.
- iCloud KVS depends on matching Apple ID and entitlements. Rollback is to keep local MacBook and Bluetooth functionality working while companion sync is disabled.
- The app is personal-use first. Mac App Store distribution requires a separate review of sandbox, Bluetooth entitlement behavior, and user-facing privacy copy.

## Self-Review

Spec coverage:
- MacBook battery: Task 3 and Task 7.
- iPhone battery: Task 5 and Task 6.
- Apple Watch battery: Task 6.
- Keyboard battery: Task 4 and Task 7.
- Additional Bluetooth devices when possible: Task 4, Task 7, Task 8.
- Elegant UI: Design Direction and Task 7.

Placeholder scan:
- No empty planning markers.
- No deferred implementation markers.
- No undefined task-level dependency without an earlier definition.

Type consistency:
- `BatterySnapshot`, `BatterySnapshotStore`, `CloudBatterySync`, `BluetoothBatteryResolver`, and `DesignTokens` names are used consistently across tasks.

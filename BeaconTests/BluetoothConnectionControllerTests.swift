import XCTest
@testable import Beacon

/// Injected observations exercise software contracts, not physical-device acceptance.
@MainActor
private final class ConnectionFixture {
    static let first = "aa:bb:cc:dd:ee:01"
    static let second = "aa:bb:cc:dd:ee:02"
    var devices: [PairedBluetoothDevice] = [
        .init(address: ConnectionFixture.first, displayName: "Same name", kind: .bluetoothPeripheral,
              isConnected: false, requiresAudioConfirmation: true),
        .init(address: ConnectionFixture.second, displayName: "Same name", kind: .bluetoothPeripheral,
              isConnected: false, requiresAudioConfirmation: true)
    ]
    var frames: [String: [BluetoothConnectionObservation]] = [:]
    var requestResult = BluetoothCommandResult()
    var denied = false
    var requests: [(String, BluetoothConnectionAction)] = []
    var client: BluetoothConnectionClient {
        .init(pairedDevices: { [self] in devices }, request: { [self] address, action in
            requests.append((address, action)); return requestResult
        }, observe: { [self] address in
            guard var observations = frames[address], let next = observations.first else {
                return .init(isPaired: devices.contains { $0.address == address }, isConnected: false)
            }
            if observations.count > 1 { observations.removeFirst(); frames[address] = observations }
            return next
        }, selectAudioOutput: { _ in 0 },
              authorizationFailure: { [self] in denied ? .permissionDenied : nil })
    }
    func controller() -> BluetoothConnectionController {
        let controller = BluetoothConnectionController(client: client, pollInterval: .milliseconds(1), maximumObservations: 6)
        controller.refreshPairedDevices(); return controller
    }
}

final class BluetoothConnectionControllerTests: XCTestCase {
    @MainActor
    private func completed(_ controller: BluetoothConnectionController, address: String) async throws -> BluetoothConnectionOperation {
        for _ in 0..<500 {
            if let operation = controller.operation(for: address), !operation.phase.isInProgress { return operation }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Injected operation did not reach a terminal state")
        return try XCTUnwrap(controller.operation(for: address))
    }

    @MainActor
    func testPairedHeadphonesWithoutBatteryRemainSelectableWithoutInventedReadings() throws {
        let controller = ConnectionFixture().controller()
        let snapshots = controller.snapshots(including: [])
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots.allSatisfy { $0.snapshot.percent == nil && $0.snapshot.readStatus == .noReport })
        XCTAssertTrue(snapshots.allSatisfy { $0.snapshot.updatedAt == .distantPast })
        let ids = controller.pairedPresentationIDs(in: snapshots)
        let items = statusMenuDeviceSections(snapshots, preferences: .init(), pairedDeviceIDs: ids).flatMap(\.items)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy(BluetoothDeviceControlSupport.canConnect))
        XCTAssertTrue(items.allSatisfy { DeviceBatteryPresentation(item: $0).percent == nil })
        let preferences = DeviceDisplayPreferences().hiding(try XCTUnwrap(items.first))
        XCTAssertEqual(statusMenuDeviceSections(snapshots, preferences: preferences, pairedDeviceIDs: ids).flatMap(\.items).count, 1)
    }

    @MainActor
    func testAcceptedCommandsAndTransientObservationsCannotInventSuccess() async throws {
        let address = ConnectionFixture.first
        let connected = BluetoothConnectionObservation(isPaired: true, isConnected: true)
        let disconnected = BluetoothConnectionObservation(isPaired: true, isConnected: false)
        let confirmed = BluetoothConnectionObservation(isPaired: true, isConnected: true, confirmedAudioOutputUID: address + ":output")
        let cases: [(BluetoothConnectionAction, [BluetoothConnectionObservation], BluetoothConnectionPhase)] = [
            (.connect, [disconnected], .timedOut),
            (.connect, [connected], .audioUnverified),
            (.connect, [confirmed, connected], .audioUnverified),
            (.connect, [connected, disconnected], .failed),
            (.disconnect, [connected], .timedOut),
            (.disconnect, [connected, disconnected], .disconnected),
            (.connect, [disconnected, connected, confirmed], .connected)
        ]
        for (action, observations, expected) in cases {
            let fixture = ConnectionFixture(); fixture.frames[address] = observations
            let controller = fixture.controller()
            XCTAssertTrue(controller.perform(action, deviceID: address, displayName: "Same name"))
            XCTAssertEqual(controller.operation(for: address)?.phase, .requesting)
            let result = try await completed(controller, address: address)
            XCTAssertEqual(result.phase, expected, "\(action): \(observations)")
            if expected != .connected { XCTAssertNil(result.audioOutputUID) }
        }
    }

    @MainActor
    func testSameNameAndRenameNeverRedirectTheRequestedIdentity() async throws {
        let fixture = ConnectionFixture()
        fixture.devices[1] = .init(address: ConnectionFixture.second, displayName: "Renamed headphones",
            kind: .bluetoothPeripheral, isConnected: false, requiresAudioConfirmation: true)
        let uid = ConnectionFixture.second + ":output"
        fixture.frames[ConnectionFixture.second] = [.init(isPaired: true, isConnected: true, confirmedAudioOutputUID: uid)]
        let controller = fixture.controller()
        controller.perform(.connect, deviceID: "bluetooth-aa-bb-cc-dd-ee-02", displayName: "Old name")
        let result = try await completed(controller, address: ConnectionFixture.second)
        XCTAssertEqual(result.phase, .connected)
        XCTAssertEqual(result.audioOutputUID, uid)
        XCTAssertEqual(result.displayName, "Renamed headphones")
        XCTAssertEqual(fixture.requests.map(\.0), [ConnectionFixture.second])
        XCTAssertNil(controller.operation(for: ConnectionFixture.first))
    }

    @MainActor
    func testDeniedAndRejectedRequestsPublishFailureWithRecoveryDetail() async throws {
        let fixture = ConnectionFixture(); fixture.denied = true
        let controller = fixture.controller()
        XCTAssertFalse(controller.perform(.connect, deviceID: ConnectionFixture.first, displayName: "Same name"))
        XCTAssertEqual(controller.operation(for: ConnectionFixture.first)?.phase, .permissionDenied)
        XCTAssertTrue(fixture.requests.isEmpty)
        fixture.denied = false; fixture.requestResult = .init(failure: .failed, errorCode: -42)
        controller.perform(.connect, deviceID: ConnectionFixture.first, displayName: "Same name")
        let result = try await completed(controller, address: ConnectionFixture.first)
        XCTAssertEqual(result.phase, .failed)
        XCTAssertTrue(result.detail.contains("-42"))
    }

    @MainActor
    func testAmbiguousOrMissingIdentityIsNotReplacedWithSameNamedDevice() {
        let fixture = ConnectionFixture(); fixture.devices = [fixture.devices[1], fixture.devices[1]]
        let controller = fixture.controller()
        XCTAssertTrue(controller.pairedDevices.isEmpty)
        XCTAssertFalse(controller.perform(.connect, deviceID: ConnectionFixture.first, displayName: "Same name"))
        XCTAssertEqual(controller.operation(for: ConnectionFixture.first)?.phase, .identityUnavailable)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertFalse(controller.perform(.connect, deviceID: "Same name", displayName: "Same name"))
        XCTAssertEqual(controller.operations.count, 1)
    }

    @MainActor
    func testLostPairingRetainsRecoveryWithoutPretendingItIsStillConnected() async throws {
        let fixture = ConnectionFixture()
        fixture.frames[ConnectionFixture.first] = [.init(isPaired: false, isConnected: false)]
        let controller = fixture.controller()
        controller.perform(.connect, deviceID: ConnectionFixture.first, displayName: "Same name")
        let result = try await completed(controller, address: ConnectionFixture.first)
        XCTAssertEqual(result.phase, .identityUnavailable)
        fixture.devices = [fixture.devices[1]]; controller.refreshPairedDevices()
        let snapshots = controller.snapshots(including: [])
        let historical = try XCTUnwrap(snapshots.first { $0.id == ConnectionFixture.first })
        XCTAssertNil(historical.snapshot.percent)
        XCTAssertEqual(historical.snapshot.connectionState, .unknown)
        let visible = statusMenuDeviceSections(snapshots, preferences: .init(),
            pairedDeviceIDs: controller.pairedPresentationIDs(in: snapshots)).flatMap(\.items)
        XCTAssertTrue(visible.contains { $0.id == ConnectionFixture.first })
    }

    @MainActor
    func testCheckResultObservesLateSuccessWithoutAnotherConnectionRequest() async throws {
        let fixture = ConnectionFixture(); let controller = fixture.controller()
        controller.perform(.connect, deviceID: ConnectionFixture.first, displayName: "Same name")
        _ = try await completed(controller, address: ConnectionFixture.first)
        let requests = fixture.requests.map(\.0)
        fixture.frames[ConnectionFixture.first] = [.init(isPaired: true, isConnected: true,
            confirmedAudioOutputUID: ConnectionFixture.first + ":output")]
        controller.perform(.connect, deviceID: ConnectionFixture.first, displayName: "Same name", verifyOnly: true)
        let result = try await completed(controller, address: ConnectionFixture.first)
        XCTAssertEqual(result.phase, .connected)
        XCTAssertEqual(fixture.requests.map(\.0), requests)
    }

    @MainActor
    func testBusyOperationCannotBeOverwrittenWhileAnotherDeviceRemainsIndependent() async throws {
        let fixture = ConnectionFixture()
        fixture.frames[ConnectionFixture.second] = [.init(isPaired: true, isConnected: true,
            confirmedAudioOutputUID: ConnectionFixture.second + ":output")]
        let controller = fixture.controller()
        controller.perform(.connect, deviceID: ConnectionFixture.first, displayName: "Same name")
        let token = controller.operation(for: ConnectionFixture.first)?.id
        XCTAssertFalse(controller.perform(.disconnect, deviceID: ConnectionFixture.first, displayName: "Same name"))
        XCTAssertEqual(controller.operation(for: ConnectionFixture.first)?.id, token)
        XCTAssertTrue(controller.perform(.connect, deviceID: ConnectionFixture.second, displayName: "Same name"))
        let first = try await completed(controller, address: ConnectionFixture.first)
        let second = try await completed(controller, address: ConnectionFixture.second)
        XCTAssertEqual(first.phase, .timedOut)
        XCTAssertEqual(second.phase, .connected)
    }

    @MainActor
    func testReconnectionDoesNotRefreshTheBatteryTimestampOrDuplicateIdentity() throws {
        let fixture = ConnectionFixture()
        fixture.devices = [.init(address: ConnectionFixture.first, displayName: "Headphones", kind: .bluetoothPeripheral,
            isConnected: true, requiresAudioConfirmation: true)]
        let controller = fixture.controller(); let time = Date(timeIntervalSince1970: 123)
        let original = DecoratedBatterySnapshot(snapshot: BatterySnapshot(deviceID: "bluetooth-aa-bb-cc-dd-ee-01",
            displayName: "Headphones", kind: .bluetoothPeripheral, percent: 42, chargeState: .unplugged,
            connectionState: .disconnected, source: .ioBluetooth, readStatus: .reported,
            identityStrength: .strong, updatedAt: time), freshness: .fresh)
        let snapshots = controller.snapshots(including: [original])
        XCTAssertEqual(snapshots.count, 1)
        let report = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(report.snapshot.percent, 42)
        XCTAssertEqual(report.snapshot.updatedAt, time)
        XCTAssertEqual(report.freshness, .stale)
        XCTAssertEqual(DeviceBatteryPresentation(item: .device(report)).state, .stale)
        XCTAssertEqual(original.snapshot.connectionState, .disconnected)
    }

    func testAudioIdentityMatchingRejectsNamesPartialAddressesAndUnknownFormats() {
        XCTAssertEqual(NativeBluetoothAudioOutput.address(fromOutputUID: "AA-BB-CC-DD-EE-01:output"), "aa:bb:cc:dd:ee:01")
        XCTAssertEqual(NativeBluetoothAudioOutput.address(fromOutputUID: "aa:bb:cc:dd:ee:01"), "aa:bb:cc:dd:ee:01")
        for uid in ["Same name", "prefix-aa:bb:cc:dd:ee:01:output", "aa:bb:cc:dd:ee:01:input",
                    "aa:bb:cc:dd:ee", "00000000-0000-0000-0000-000000000000"] {
            XCTAssertNil(NativeBluetoothAudioOutput.address(fromOutputUID: uid), uid)
        }
    }
}

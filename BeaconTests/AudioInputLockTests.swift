import XCTest
@testable import Beacon

@MainActor
final class AudioInputLockTests: XCTestCase {
    private let builtIn = AudioInputDevice(uid: "BuiltInMic", name: "MacBook Air Microphone", transport: .builtIn)
    private let airPods = AudioInputDevice(uid: "AA-BB:input", name: "AirPods Pro", transport: .bluetooth)
    private let usb = AudioInputDevice(uid: "USB-1", name: "Shure MV7", transport: .usb)

    func testLockRestoresPreferredInputWhenSomethingElseTakesOver() {
        let system = FakeAudioInputSystem(devices: [builtIn, airPods, usb], current: usb.uid)
        let controller = makeController(system, preferred: usb.uid)
        controller.start()

        system.simulateExternalSwitch(to: airPods.uid)

        XCTAssertEqual(system.current, usb.uid)
        XCTAssertEqual(controller.lastRestoration, .init(restoredName: "Shure MV7", blockedName: "AirPods Pro"))
    }

    func testLockUsesFallbackWhenPreferredIsMissingAndReturnsWhenItReconnects() {
        let system = FakeAudioInputSystem(devices: [builtIn, airPods], current: airPods.uid)
        let controller = makeController(system, preferred: usb.uid, fallback: builtIn.uid)
        controller.start()
        XCTAssertEqual(system.current, builtIn.uid)

        system.simulateDeviceList([builtIn, airPods, usb])
        XCTAssertEqual(system.current, usb.uid)
    }

    func testDisabledLockNeverSwitches() {
        let system = FakeAudioInputSystem(devices: [builtIn, airPods], current: airPods.uid)
        let defaults = makeDefaults()
        AudioInputLockPreferences(isEnabled: false, preferredUID: builtIn.uid).save(to: defaults)
        let controller = AudioInputController(system: system, defaults: defaults)
        controller.start()

        XCTAssertEqual(system.current, airPods.uid)
        XCTAssertNil(controller.lastRestoration)
    }

    func testLockReportsNothingWhenSwitchIsRefused() {
        let system = FakeAudioInputSystem(devices: [builtIn, airPods], current: airPods.uid)
        system.refusesSwitches = true
        let controller = makeController(system, preferred: builtIn.uid)
        controller.start()

        XCTAssertNil(controller.lastRestoration)
    }

    func testHeadsetMicrophoneToggleMovesBetweenBluetoothAndBuiltIn() {
        let system = FakeAudioInputSystem(devices: [builtIn, airPods], current: airPods.uid)
        let controller = AudioInputController(system: system, defaults: makeDefaults())

        XCTAssertEqual(controller.toggleHeadsetMicrophone(), "MacBook Air Microphone")
        XCTAssertEqual(system.current, builtIn.uid)
        XCTAssertEqual(controller.toggleHeadsetMicrophone(), "AirPods Pro")
        XCTAssertEqual(system.current, airPods.uid)
    }

    func testHeadsetMicrophoneToggleWithoutHeadsetDoesNothing() {
        let system = FakeAudioInputSystem(devices: [builtIn], current: builtIn.uid)
        let controller = AudioInputController(system: system, defaults: makeDefaults())
        XCTAssertNil(controller.toggleHeadsetMicrophone())
    }

    func testToggleLockAdoptsCurrentInputWhenNoPreferenceExists() {
        let system = FakeAudioInputSystem(devices: [builtIn, airPods], current: builtIn.uid)
        let controller = AudioInputController(system: system, defaults: makeDefaults())

        XCTAssertTrue(controller.toggleLock())
        XCTAssertEqual(controller.preferences.preferredUID, builtIn.uid)
    }

    private func makeController(_ system: FakeAudioInputSystem, preferred: String, fallback: String? = nil) -> AudioInputController {
        let defaults = makeDefaults()
        AudioInputLockPreferences(isEnabled: true, preferredUID: preferred, fallbackUID: fallback).save(to: defaults)
        return AudioInputController(system: system, defaults: defaults)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "AudioInputLockTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }
}

@MainActor
private final class FakeAudioInputSystem: AudioInputSystem {
    private(set) var devices: [AudioInputDevice]
    private(set) var current: String?
    var refusesSwitches = false
    private var onChange: (@MainActor () -> Void)?

    init(devices: [AudioInputDevice], current: String?) {
        self.devices = devices
        self.current = current
    }

    func inputDevices() -> [AudioInputDevice] { devices }
    func defaultInputUID() -> String? { current }

    func setDefaultInput(uid: String) -> Bool {
        guard !refusesSwitches, devices.contains(where: { $0.uid == uid }) else { return false }
        current = uid
        onChange?()
        return true
    }

    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func simulateExternalSwitch(to uid: String) {
        current = uid
        onChange?()
    }

    func simulateDeviceList(_ devices: [AudioInputDevice]) {
        self.devices = devices
        onChange?()
    }
}

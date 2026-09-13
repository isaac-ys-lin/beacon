import Foundation
@preconcurrency import IOBluetooth
import CoreBluetooth
import CoreAudio
import IOKit

@MainActor
extension BluetoothConnectionClient {
    static func live() -> Self {
        let backend = NativeBluetoothConnectionBackend()
        return Self(pairedDevices: { backend.pairedDevices() },
                    request: { backend.request(address: $0, action: $1) },
                    observe: { backend.observe(address: $0) },
                    selectAudioOutput: { NativeBluetoothAudioOutput.select(address: $0) },
                    authorizationFailure: {
                        CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted
                            ? .permissionDenied : nil
                    })
    }
}

/// This target is retained while its asynchronous request is outstanding. Each request gets
/// its own receiver, so a late callback cannot overwrite a newer request's result.
@MainActor
private final class BluetoothConnectionReply: NSObject {
    var status: IOReturn?

    @objc(connectionComplete:status:)
    nonisolated func connectionComplete(_ device: IOBluetoothDevice?, status: IOReturn) {
        Task { @MainActor [weak self] in self?.status = status }
    }
}

@MainActor
private final class NativeBluetoothConnectionBackend {
    private var replies: [String: BluetoothConnectionReply] = [:]
    private var outstandingReplies: [BluetoothConnectionReply] = []

    func pairedDevices() -> [PairedBluetoothDevice] {
        guard !permissionDenied else { return [] }
        return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { device in
            guard device.isPaired(), let rawAddress = device.addressString,
                  let address = BluetoothDeviceControlSupport.normalizedAddress(from: rawAddress) else { return nil }
            // Audio/video, HID peripherals, and unclassified paired accessories. Phones and
            // computers keep their existing setup flows; no cross-Mac transfer is introduced.
            let major = device.deviceClassMajor
            guard major == 0 || major == kBluetoothDeviceClassMajorAudioVideo
                    || major == kBluetoothDeviceClassMajorPeripheral else { return nil }
            let kind: DeviceKind
            if major == kBluetoothDeviceClassMajorPeripheral {
                kind = device.deviceClassMinor & 0x10 != 0 ? .keyboard : .bluetoothPeripheral
            } else {
                kind = .bluetoothPeripheral
            }
            return PairedBluetoothDevice(address: address, displayName: device.name ?? address,
                kind: kind, isConnected: device.isConnected(),
                requiresAudioConfirmation: major != kBluetoothDeviceClassMajorPeripheral)
        }
    }

    func request(address: String, action: BluetoothConnectionAction) -> BluetoothCommandResult {
        guard !permissionDenied else { return .init(failure: .permissionDenied) }
        guard let device = pairedDevice(address: address) else { return .init(failure: .identityUnavailable) }
        outstandingReplies.removeAll { $0.status != nil }
        replies[address] = nil
        let code: IOReturn
        switch action {
        case .connect:
            if device.isConnected() { return .init() }
            let reply = BluetoothConnectionReply()
            replies[address] = reply
            outstandingReplies.append(reply)
            // Non-nil target makes this asynchronous. A successful return is only acceptance.
            code = device.openConnection(reply, withPageTimeout: 0x2000, authenticationRequired: false)
            if code != kIOReturnSuccess { reply.status = code }
        case .disconnect:
            if !device.isConnected() { return .init() }
            code = device.closeConnection()
        }
        return code == kIOReturnSuccess ? .init() : .init(failure: failurePhase(code), errorCode: code)
    }

    func observe(address: String) -> BluetoothConnectionObservation {
        guard !permissionDenied else {
            return .init(isPaired: false, isConnected: false, failure: .permissionDenied)
        }
        guard let device = pairedDevice(address: address) else {
            return .init(isPaired: false, isConnected: false)
        }
        let code = replies[address]?.status
        return BluetoothConnectionObservation(isPaired: true, isConnected: device.isConnected(),
            confirmedAudioOutputUID: NativeBluetoothAudioOutput.confirmedUID(address: address),
            failure: code.flatMap { $0 == kIOReturnSuccess ? nil : failurePhase($0) },
            errorCode: code == kIOReturnSuccess ? nil : code)
    }

    private var permissionDenied: Bool {
        CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted
    }

    private func pairedDevice(address: String) -> IOBluetoothDevice? {
        let matches = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
            $0.isPaired() && $0.addressString.flatMap { BluetoothDeviceControlSupport.normalizedAddress(from: $0) } == address
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func failurePhase(_ code: IOReturn) -> BluetoothConnectionPhase {
        if code == kIOReturnNotPermitted || code == kIOReturnNotPrivileged { return .permissionDenied }
        return code == kIOReturnTimeout ? .timedOut : .failed
    }
}

/// Conservative interoperability boundary: accept only a Bluetooth output UID that encodes
/// the complete device address, optionally followed by ':output'. Never match display names
/// or assume every vendor/macOS UID has this format. Unknown/ambiguous UIDs remain unconfirmed.
enum NativeBluetoothAudioOutput {
    static func address(fromOutputUID uid: String) -> String? {
        let value = uid.hasSuffix(":output") ? String(uid.dropLast(7)) : uid
        guard value.count == 17 else { return nil }
        return BluetoothDeviceControlSupport.normalizedAddress(from: value)
    }

    static func confirmedUID(address: String) -> String? {
        guard let output = uintProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
              let uid = matchingUID(device: output, address: address),
              uintProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) == output
        else { return nil }
        return uid
    }

    static func select(address: String) -> OSStatus? {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr,
              size > 0, size % UInt32(MemoryLayout<AudioDeviceID>.size) == 0 else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(system, &property, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { return status }
        let matches = devices.filter { matchingUID(device: $0, address: address) != nil }
        guard matches.count == 1 else { return nil }
        var selected = matches[0]
        var outputProperty = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        // Read-back happens on a later observe() call, not by returning the value just set.
        return AudioObjectSetPropertyData(system, &outputProperty, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &selected)
    }

    private static func matchingUID(device: AudioDeviceID, address: String) -> String? {
        guard let transport = uintProperty(device, kAudioDevicePropertyTransportType),
              transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
              uintProperty(device, kAudioDevicePropertyDeviceIsAlive) == 1,
              let uid = stringProperty(device, kAudioDevicePropertyDeviceUID),
              self.address(fromOutputUID: uid) == address else { return nil }
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size > 0 else { return nil }
        return uid
    }

    private static func uintProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value as String?
    }
}

from pathlib import Path
import json

p = Path('Beacon/Mac/BeaconSettingsView.swift')
s = p.read_text()
block = '''            if BluetoothDeviceControlSupport.normalizedAddress(from: row.id) != nil {
                BluetoothConnectionControls(item: row.item, controller: connections)
                    .beaconSettingsCardSurface()
            }
'''
assert block in s
s = s.replace(block, '', 1)
s = s.replace('            DeviceCurrentStatsCard(\n                item: row.item,', block + '\n            DeviceCurrentStatsCard(\n                item: row.item,', 1)
old = '            }\n\n\n            HStack {\n                if row.isUserHidden'
new = '''            }

            DisclosureGroup("Refresh Diagnostics") {
                RefreshHealthDisclosureView(diagnostics: refreshDiagnostics)
            }
            .font(.caption)

            HStack {
                if row.isUserHidden'''
assert old in s
p.write_text(s.replace(old, new, 1))

p = Path('Beacon/Mac/BluetoothConnectionController.swift')
s = p.read_text().replace('    let action: BluetoothConnectionAction\n    var phase:', '    let action: BluetoothConnectionAction\n    var kind: DeviceKind = .bluetoothPeripheral\n    var phase:')
s = s.replace('            phase: .requesting, detail:', '            kind: target?.kind ?? .bluetoothPeripheral,\n            phase: .requesting, detail:')
start = s.index('                guard observation.isPaired else {')
end = s.index('                let linkMatches', start)
block = s[start:end]; split = block.index('                if let failure')
s = s[:start] + block[split:] + block[:split] + s[end:]
s = s.replace('filter { device(for: $0.id) != nil }.map', 'filter { device(for: $0.id) != nil || operation(for: $0.id) != nil }.map')
s = s.replace('            represented.insert(paired.address)\n            return Decorated', '''            represented.insert(paired.address)
            // A reconnection does not refresh the battery report or its timestamp.
            let freshness: Freshness = paired.isConnected && s.connectionState != .connected
                && decorated.freshness == .fresh ? .stale : decorated.freshness
            return Decorated''')
s = s.replace('updatedAt: s.updatedAt), freshness: decorated.freshness)', 'updatedAt: s.updatedAt), freshness: freshness)')
s = s.replace('        for paired in pairedDevices where !represented.contains(paired.address) {\n            result.append', '        for paired in pairedDevices where !represented.contains(paired.address) {\n            represented.insert(paired.address)\n            result.append')
s = s.replace('        // These synthetic entries are presentation-only: never write them to battery history.\n        return result', '''        // A vanished paired identity must not also remove its failure/recovery entry.
        let snapshotAddresses = Set(snapshots.compactMap {
            BluetoothDeviceControlSupport.normalizedAddress(from: $0.id)
        })
        for operation in operations.values.sorted(by: { $0.address < $1.address })
            where !represented.contains(operation.address) && !snapshotAddresses.contains(operation.address) {
            result.append(DecoratedBatterySnapshot(snapshot: BatterySnapshot(deviceID: operation.deviceID,
                displayName: operation.displayName, kind: operation.kind, percent: nil, chargeState: .unknown,
                connectionState: .unknown, source: .ioBluetooth, readStatus: .noReport,
                identityStrength: .strong, updatedAt: .distantPast), freshness: .expired))
        }
        // Presentation only: never persist these entries as battery history.
        return result''')
p.write_text(s)
p = Path('Beacon/Mac/BeaconStatusController.swift')
s = p.read_text().replace('snapshots: model.connections.snapshots(including: model.store.decoratedSnapshots),\n            preferences:', 'snapshots: model.connections.snapshots(including: model.store.decoratedSnapshots).filter {\n                model.connections.device(for: $0.id) != nil\n            },\n            preferences:')
p.write_text(s)
p = Path('Beacon/Mac/NativeBluetoothConnectionClient.swift')
s = p.read_text().replace('.init(isPaired: true, isConnected: false, failure: .permissionDenied)', '.init(isPaired: false, isConnected: false, failure: .permissionDenied)')
s = s.replace('              let uid = matchingUID(device: output, address: address) else { return nil }\n        return uid', '              let uid = matchingUID(device: output, address: address),\n              uintProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) == output\n        else { return nil }\n        return uid')
p.write_text(s)

translations = {
'Sending connection request':'正在送出連線要求', 'Checking Bluetooth connection':'正在確認藍牙連線',
'Checking audio output':'正在確認音訊輸出', 'Connection confirmed':'已確認連線',
'Disconnection confirmed':'已確認斷線', 'Connection change failed':'連線操作失敗',
'Connection result not confirmed':'尚未確認連線結果',
'Bluetooth connected; audio not confirmed':'藍牙已連線；音訊尚未確認',
'Paired device identity unavailable':'無法確認已配對裝置身分', 'Bluetooth permission required':'需要藍牙權限',
'A request is not a confirmed result.':'送出要求不代表操作已完成。',
'Allow Beacon in Bluetooth Privacy Settings, then check again.':'請在藍牙隱私權設定中允許 Beacon，再重新檢查。',
'Pair the exact device in Bluetooth Settings, then check again. Beacon will not choose a same-named device.':'請在藍牙設定中配對這台裝置，再重新檢查。Beacon 不會改選同名裝置。',
'Waiting for macOS to confirm the actual device state.':'正在等待 macOS 確認裝置的實際狀態。',
'The paired identity disappeared while checking. No other device was selected.':'檢查時已無法確認原配對身分；未選取其他裝置。',
'macOS reports that this Bluetooth link is disconnected.':'macOS 已回報這台裝置的藍牙連線中斷。',
'Bluetooth and the default audio output were independently confirmed.':'已分別確認藍牙連線與預設音訊輸出。',
'macOS reports that this Bluetooth link is connected.':'macOS 已回報這台裝置的藍牙連線建立。',
'The connection dropped before confirmation. Keep the device nearby and retry.':'完成確認前連線已中斷，請讓裝置保持在附近並重試。',
'Bluetooth is connected. Audio output still needs independent confirmation.':'藍牙已連線，音訊輸出仍須另行確認。',
'Open Sound Settings, select the intended output, then Check Result. An unmapped audio identity is not treated as success.':'請開啟聲音設定、選取正確輸出，再按「檢查結果」。無法對應音訊身分時不會判定成功。',
'macOS did not confirm the requested state before the deadline. Check the device and retry; the system request may still complete later.':'期限內 macOS 未確認要求的狀態，請檢查裝置並重試；系統要求仍可能稍後完成。',
'macOS rejected the request. Check Bluetooth permission, pairing and device availability, then retry.':'macOS 拒絕要求，請檢查藍牙權限、配對及裝置狀態，再重試。',
'Last operation result':'上次操作結果', 'This device is not in the current paired-device list.':'目前的配對清單中沒有這台裝置。',
'Connection control does not require a battery report.':'沒有電量報告也能操作連線。',
'Device identity: %@':'裝置識別碼：%@', 'Use for Audio':'設為音訊輸出', 'Check Result':'檢查結果',
'Connection Details':'連線詳細資訊',
'Device names are not used to match Bluetooth identities or audio outputs.':'不會以裝置名稱比對藍牙身分或音訊輸出。'
}
p = Path('Beacon/Mac/zh-Hant-TW.lproj/Localizable.strings'); s = p.read_text()
for key, value in translations.items():
    if json.dumps(key, ensure_ascii=False) + ' =' not in s:
        s += json.dumps(key, ensure_ascii=False) + ' = ' + json.dumps(value, ensure_ascii=False) + ';\n'
p.write_text(s)

from pathlib import Path

p = Path('Beacon/Mac/BeaconStatusController.swift'); s = p.read_text()
s = s.replace('    private var connectionObserver:', '    private var operationObserver: AnyCancellable?\n    private var lastHUDOperations: [String: BluetoothConnectionOperation] = [:]\n    private var connectionObserver:', 1)
s = s.replace('        connectionObserver = model.connections.objectWillChange', '''        hudController.onReviewOperation = { [weak self] deviceID in
            self?.showSettingsWindow(initialPane: .devices, selectedDeviceID: deviceID)
        }
        operationObserver = model.connections.$operations.sink { [weak self] operations in
            guard let self else { return }
            for operation in operations.values.sorted(by: { $0.address < $1.address }) {
                guard self.lastHUDOperations[operation.address] != operation else { continue }
                self.lastHUDOperations[operation.address] = operation
                self.hudController.show(operation: operation)
            }
        }
        connectionObserver = model.connections.objectWillChange''', 1)
s = s.replace('                self?.hudController.show(event: events[0])', '                for event in events { self?.hudController.show(event: event) }', 1)
s = s.replace('    func showHUDForUITesting() {\n', '''    func showHUDForUITesting() {
        if ProcessInfo.processInfo.environment["BEACON_HUD_SCENARIO"] == "connection-events" {
            hudController.prepareOperationUITesting()
            model.connections.perform(.connect, deviceID: "bluetooth-aa-bb-cc-dd-ee-02", displayName: "Test Headphones")
            hudController.exposeWindowToAccessibilityForUITesting()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.hudController.showForUITesting(event: BatteryAlertEvent(kind: .lowBattery,
                    deviceID: "ui-test-device", displayName: "Queued Keyboard", percent: 12))
            }
            return
        }
''', 1)
s = s.replace('    private func handlePreferencesChanged() {\n', '    private func handlePreferencesChanged() {\n        hudController.refreshPreferences()\n', 1)
p.write_text(s)
p = Path('Beacon/Mac/BeaconHUDView.swift'); s = p.read_text()
s = s.replace('                .help("Dismiss")', '                .help("Dismiss")\n                .accessibilityLabel("Dismiss")\n                .accessibilityIdentifier("hud.dismiss")', 1)
p.write_text(s)
p = Path('Beacon/Mac/zh-Hant-TW.lproj/Localizable.strings')
p.write_text(p.read_text() + '\n"Review Result" = "查看結果";\n')

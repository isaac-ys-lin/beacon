from pathlib import Path

p = Path('Beacon/Mac/BeaconMacApp.swift'); s = p.read_text()
s = s.replace('            "--ui-test-show-hud",', '            "--ui-test-show-desktop",\n            "--ui-test-show-hud",')
old = '''        if arguments.contains("--ui-test-open-status-menu") {
            statusController?.showStatusMenuForUITesting()
        }'''
assert old in s
s = s.replace(old, old + '''
        if arguments.contains("--ui-test-show-desktop") {
            statusController?.showDesktopWidgetForUITesting()
        }''', 1)
p.write_text(s)

p = Path('Beacon/Mac/BeaconStatusController.swift'); s = p.read_text()
old = '''    func showSettingsForUITesting() {
        showSettingsWindow(initialPane: .devices)
    }'''
new = '''    func showSettingsForUITesting() {
        showSettingsWindow(initialPane: .devices)
        if ProcessInfo.processInfo.environment["BEACON_SETTINGS_MINIMUM_SIZE"] == "1" {
            settingsWindowController.debugWindow?.setContentSize(NSSize(width: 900, height: 620))
        }
    }

    func showDesktopWidgetForUITesting() {
        // Use the same presentation and routing as the user's actual desktop panel.
        // The test sets visibility/style through the argument domain, not saved preferences.
        updateDesktopWidget()
        desktopWidgetController.exposeWindowToAccessibilityForUITesting()
    }'''
assert old in s; p.write_text(s.replace(old, new, 1))

p = Path('Beacon/Mac/BeaconDesktopWidgetView.swift'); s = p.read_text()
s = s.replace('if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {', '''if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("--ui-test-show-desktop") {''', 1)
s = s.replace('        .preferredColorScheme(appearanceTheme.colorSchemeOverride)', '''        .preferredColorScheme(appearanceTheme.colorSchemeOverride)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("desktop.widget")''', 1)
s = s.replace('                Text(latestUpdateText)\n', '                Text(latestUpdateText)\n                    .accessibilityIdentifier("desktop.report-time")\n', 1)
s = s.replace('    #if DEBUG\n    var debugWindowFrame:', '''    #if DEBUG
    // Same narrow AX adapter as the HUD/menu tests. Production stays nonactivating.
    func exposeWindowToAccessibilityForUITesting() {
        guard let window else { return }
        let size = window.contentRect(forFrameRect: window.frame).size
        window.styleMask.remove(.nonactivatingPanel)
        window.styleMask.formUnion([.titled, .fullSizeContentView])
        window.title = "Beacon Desktop Widget"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
    }

    var debugWindowFrame:''', 1)
p.write_text(s)

p = Path('Beacon/Mac/BeaconSettingsWindowController.swift'); s = p.read_text()
s = s.replace('        let autosaveName = "Beacon.SettingsWindow"', '''        var autosaveName = "Beacon.SettingsWindow"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-test-") }) {
            autosaveName += ".UITests"
        }
        #endif''', 1)
p.write_text(s)

p = Path('BeaconUITests/BeaconUITests.swift'); s = p.read_text()
s = s.replace('for pane in ["quickActions", "alerts", "actionHUD", "dashboard"] {', 'for pane in ["general", "devices", "quickActions", "alerts", "actionHUD", "dashboard"] {', 1)
s = s.replace('            switch pane {\n            case "quickActions":', '''            switch pane {
            case "general":
                XCTAssertTrue(window.buttons["general.history.export"].waitForExistence(timeout: 5))
                XCTAssertTrue(window.buttons["general.launch-at-login.refresh"].exists)
            case "devices":
                XCTAssertTrue(window.buttons["settings.refresh"].waitForExistence(timeout: 5))
                XCTAssertTrue(window.buttons["settings.iphone-setup"].exists)
            case "quickActions":''', 1)
old = '''        app.launchArguments = ["--ui-test-open-settings", "-AppleLanguages", "(\\(language))", "-Beacon.appearanceTheme", theme]
        app.launchEnvironment["BEACON_PREVIEW_DATA"] = "1"'''
assert old in s
s = s.replace(old, old + '\n        app.launchEnvironment["BEACON_SETTINGS_MINIMUM_SIZE"] = "1"', 1)
p.write_text(s)

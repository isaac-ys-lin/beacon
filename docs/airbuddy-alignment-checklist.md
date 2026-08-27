# Beacon AirBuddy Alignment Checklist

Last verified: 2026-08-27

## Reference Scope

AirBuddy was used as the product reference for the device-status experience, not
as a request to clone private implementation details. The reference areas used
for this pass are:

- Menu bar device overview and status window.
- Rich AirPods and peripheral battery display.
- Battery alerts for low and fully charged states.
- Device-level context actions from the menu bar list.
- Pairing and Bluetooth settings flows.
- Global quick actions and Shortcuts integration.
- AirPods listening mode and microphone preference surfaces.
- Settings for device visibility and alert behavior.
- Widget/dashboard style glanceability.

Current product boundary:

- Direct-download macOS 14+ app only.
- No Mac App Store target, iOS/watch companion, iCloud sync, private APIs,
  paid licensing, third-party network service, or in-app network updater.
- Device transfer and Magic Handoff style behavior remain excluded.

Official reference links reviewed:

- https://v2.airbuddy.app/
- https://support.airbuddy.app/
- https://support.airbuddy.app/articles/how-to-configure-battery-alerts-for-devices-in-airbuddy/
- https://support.airbuddy.app/articles/how-to-change-listening-modes-using-airbuddy/
- https://support.airbuddy.app/articles/how-to-enable-disable-microphone-input-using-airbuddy/
- https://support.airbuddy.app/articles/how-to-manually-pair-airpods-or-beats-devices-using-airbuddy/
- https://support.airbuddy.app/articles/how-to-remove-or-ignore-devices-in-airbuddy/

## Implemented Alignment

| Feature area | Production implementation | Verification coverage | Status |
| --- | --- | --- | --- |
| Menu/status window behavior | `Beacon/Mac/BeaconMacApp.swift`, `Beacon/Mac/StatusMenuView.swift` | `testStatusMenuViewPreviewRenderProducesNonBlankImage`, `testStatusMenuViewRefreshingRenderProducesNonBlankImage`, `testStatusMenuSettingsPreviewRenderProducesNonBlankImage` | Complete |
| Device cards and battery/status display | `Beacon/Mac/DeviceBatteryRow.swift`, `Beacon/Mac/StatusMenuView.swift`, `Beacon/Mac/DeviceListPresentation.swift`, `Beacon/Shared/BatterySnapshot.swift` | `testStatusMenuViewPreviewRenderProducesNonBlankImage`, snapshot store compatibility tests, resolver tests | Complete |
| AirPods multi-component display | `Beacon/Mac/DeviceBatteryRow.swift`, `Beacon/Mac/StatusMenuView.swift`, `Beacon/Mac/DeviceListPresentation.swift` | `testAirPodsThreeComponentAggregation`, `testAirPodsComponentsCanHaveNilPercent`, `testSystemProfilerParserSplitsConnectedAirPodsBatteryComponents`, AirPods render tests | Complete |
| Pairing and connect flows | `Beacon/Mac/BeaconSettingsView.swift`, `Beacon/Mac/BeaconMacApp.swift`, `Beacon/Mac/BluetoothDeviceScanner.swift`, `Beacon/Mac/DeviceListPresentation.swift` | `testAddDeviceGuideRenderProducesNonBlankImage`, context action and control target tests | Complete with platform-safe limits |
| Device context actions | `Beacon/Mac/StatusMenuView.swift`, `Beacon/Mac/DeviceListPresentation.swift`, `Beacon/Mac/BeaconQuickActions.swift` | `testContextMenuActionsExposeSafeImplementedCommandsFirst`, `testContextMenuActionTitlesMatchAirBuddyStyleCommands`, `testAirPodsContextMenuIncludesAudioControls` | Complete |
| Preferences and settings window | `Beacon/Mac/BeaconSettingsView.swift`, `Beacon/Mac/DeviceListPresentation.swift`, `Beacon/Mac/BeaconHUDView.swift`, `Beacon/Mac/BeaconQuickActions.swift` | `testBeaconSettingsWindowRenderProducesNonBlankImage`, `testBeaconSettingsWindowRefreshingRenderProducesNonBlankImage`, settings tab render tests | Complete |
| General settings and app lifecycle | `Beacon/Mac/GeneralSettingsPane.swift`, `Beacon/Mac/GeneralSettingsSupport.swift` | launch-at-login state/action tests, version fallback test, General pane render test | Complete for signed direct-download builds |
| Local data controls | `Beacon/Mac/GeneralSettingsPane.swift`, `Beacon/Mac/GeneralSettingsSupport.swift`, `Beacon/Shared/BatteryHistoryStore.swift` | CSV escaping/order/clear tests and preference-reset preservation test | Complete |
| Battery alerts | `Beacon/Mac/LowBatteryNotifier.swift`, `Beacon/Mac/BeaconHUDView.swift`, settings alert panes | `testLowBatteryNotifierFallsBackToAirPodsPrefixThreshold`, `testChargedAlertRequiresDeviceOptInAndCreatesEventOnceUntilDrained`, `testBeaconAlertsCanRenderInitialSelectedDeviceOverrides`, HUD render tests | Complete |
| Shortcuts and automation | `Beacon/Mac/BeaconAppShortcuts.swift`, `Beacon/Mac/BeaconQuickActions.swift`, `Beacon/Mac/BeaconMacApp.swift` | `testBeaconAppShortcutsExposeSupportedAutomationActions`, intent bridge tests, app intents metadata extraction in packaged app | Complete |
| Quick actions and keyboard shortcuts | `Beacon/Mac/BeaconQuickActions.swift`, `Beacon/Mac/BeaconMacApp.swift`, quick actions settings pane | `testQuickActionPreferencesDefaultToSafeEnabledActions`, `testQuickActionPreferencesRoundTripAndFilterUnsupportedActions`, `testBeaconQuickActionsSettingsRenderProducesNonBlankImage` | Complete |
| English and Taiwan Traditional Chinese | `Beacon/Shared/BeaconL10n.swift`, `Beacon/Mac/zh-Hant-TW.lproj` | bundle localization test, Xcode localization export audit, App Shortcuts strings validation | Complete for current user-facing strings |
| AirPods audio controls | `Beacon/Mac/DeviceListPresentation.swift`, `Beacon/Mac/StatusMenuView.swift`, `Beacon/Mac/BeaconSettingsView.swift` | `testAirPodsAudioPreferencesRoundTripPerDevice`, `testBeaconSettingsWindowCanRenderAirPodsAudioControls` | Safe alternative implemented |
| Widget/dashboard glanceability | `Beacon/Mac/BeaconDesktopWidgetView.swift`, `Beacon/Mac/BeaconSettingsView.swift`, `Beacon/Shared/BatteryHistoryStore.swift` | `testBatteryDesktopWidgetRenderProducesNonBlankImage`, `testBeaconDashboardSettingsRenderProducesDesktopWidgetPreview`, history trend tests | Complete |
| Empty/loading/stale/unsupported states | `Beacon/Mac/StatusMenuView.swift`, `Beacon/Mac/BeaconSettingsView.swift`, `Beacon/Mac/DeviceBatteryRow.swift`, `Beacon/Shared/BatterySnapshotStore.swift` | refreshing render tests, `testUnsupportedBluetoothDeviceStaysVisibleWithoutPercent`, freshness/status render coverage | Complete |
| Preserve existing working behavior | `Beacon/Shared/BatterySnapshotStore.swift`, `Beacon/Mac/BluetoothDeviceScanner.swift`, USB-first `ideviceinfo` iPhone battery provider | Full current test suite, resolver tests, snapshot compatibility tests | Complete |
| Production app folder/build integration | `Beacon.xcodeproj/project.pbxproj`, `script/build_and_run.sh`, `script/package_dmg.sh`, new files under `Beacon/Mac` and `Beacon/Shared` | Xcode build/test/package verification, codesign verify, DMG verify | Complete with signing limits |
| Device transfer / Magic Handoff exclusion | `Beacon/Mac/BeaconQuickActions.swift` keeps `transferToMac` unsupported and filtered from defaults | `testQuickActionPreferencesDefaultToSafeEnabledActions`, `testQuickActionPreferencesRoundTripAndFilterUnsupportedActions` | Excluded as requested |

## Platform And Product Limits

These limits are intentional, documented, and handled with production-safe
alternatives:

- Direct AirPods listening mode and microphone switching is not implemented with
  private APIs. Beacon stores the desired per-device preference, exposes the
  preference in the status/settings UI, and opens macOS Sound or Bluetooth
  Settings for the actual system-level change.
- Real Bluetooth connect/disconnect live testing was not run against the user's
  devices because it would change local device state. The app routes through
  macOS-supported command paths when a paired Bluetooth address is available,
  and tests cover support detection and action selection.
- The scanner degrades quietly for transient Bluetooth/system-profiler misses:
  the status menu shows only fresh connected reports, while Settings can still
  collapse hidden or unavailable devices for recovery.
- Beacon is currently a macOS-only menu bar app. iPhone battery support is read
  locally from trusted devices through the external `ideviceinfo` command,
  preferring USB and falling back to Wi-Fi lockdown when available; there are no
  active iOS/watch companion targets or iCloud battery sync path in the current
  project.
- Apple Watch remains a model/test-preview compatibility type only. The
  production app has no Apple Watch data provider and makes no support claim.
- Launch at Login uses Apple's `SMAppService.mainApp`. An unsigned test build can
  correctly report the service as unavailable; the signed direct-download build
  exposes registration, required-approval, and error states without fake success.
- Updates are manual. Beacon does not call an update server or download code in
  the background.
- The local DMG is ad-hoc signed when `DEVELOPER_ID_IDENTITY` is not provided.
  Developer ID signing and notarization require those external signing
  credentials.

## Verification Evidence

Current evidence from 2026-08-27:

- `git diff --check` passed.
- The complete `BeaconMac` test suite passed with 216 tests and 0 failures,
  including minimum-window render coverage for General, Action HUD, and AirPods
  detail panes so taller content cannot push the settings chrome off-screen.
- `script/build_and_run.sh --verify` produced an Apple Development-signed Debug
  app and verified the active process was running that exact executable.
- `codesign --verify --deep --strict --verbose=2` passed for the signed Debug app;
  its entitlements contain Bluetooth and development debugging access, but no App
  Sandbox entitlement.
- Xcode localization export found zero untranslated units for `zh-Hant-TW`,
  including App Shortcut phrases.
- App Intents metadata extraction succeeded and the test suite confirms the
  platform-limit maximum of 10 App Shortcuts.
- `script/package_dmg.sh` built the Release app and produced a locally ad-hoc
  signed `dist/Beacon.dmg`; no install, notarization, publication, commit, or push
  was performed.
- Render artifacts used for screen inspection include:
  - `/tmp/batteryhub-status-menu-render.png`
  - `/tmp/batteryhub-status-menu-refreshing-render.png`
  - `/tmp/batteryhub-settings-refreshing-render.png`
  - `/tmp/batteryhub-airpods-settings-render.png`
  - `/tmp/batteryhub-alerts-empty-render.png`
  - `/tmp/batteryhub-action-hud-settings-render.png`
  - `/tmp/batteryhub-quick-actions-settings-render.png`
  - `/tmp/batteryhub-general-settings-render.png`

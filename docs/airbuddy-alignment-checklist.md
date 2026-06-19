# BatteryHub AirBuddy Alignment Checklist

Generated: 2026-06-18

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

Out of scope by user request:

- Device transfer and Magic Handoff style behavior.

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
| Menu/status window behavior | `BatteryHub/Mac/BatteryHubMacApp.swift`, `BatteryHub/Mac/StatusMenuView.swift` | `testStatusMenuViewPreviewRenderProducesNonBlankImage`, `testStatusMenuViewRefreshingRenderProducesNonBlankImage`, `testStatusMenuSettingsPreviewRenderProducesNonBlankImage` | Complete |
| Device cards and battery/status display | `BatteryHub/Mac/DeviceBatteryRow.swift`, `BatteryHub/Mac/StatusMenuView.swift`, `BatteryHub/Mac/DeviceListPresentation.swift`, `BatteryHub/Shared/BatterySnapshot.swift` | `testStatusMenuViewPreviewRenderProducesNonBlankImage`, snapshot store compatibility tests, resolver tests | Complete |
| AirPods multi-component display | `BatteryHub/Mac/DeviceBatteryRow.swift`, `BatteryHub/Mac/StatusMenuView.swift`, `BatteryHub/Mac/DeviceListPresentation.swift` | `testAirPodsThreeComponentAggregation`, `testAirPodsComponentsCanHaveNilPercent`, `testSystemProfilerParserSplitsConnectedAirPodsBatteryComponents`, AirPods render tests | Complete |
| Pairing and connect flows | `BatteryHub/Mac/BatteryHubSettingsView.swift`, `BatteryHub/Mac/BatteryHubMacApp.swift`, `BatteryHub/Mac/BluetoothDeviceScanner.swift`, `BatteryHub/Mac/DeviceListPresentation.swift` | `testAddDeviceGuideRenderProducesNonBlankImage`, context action and control target tests | Complete with platform-safe limits |
| Device context actions | `BatteryHub/Mac/StatusMenuView.swift`, `BatteryHub/Mac/DeviceListPresentation.swift`, `BatteryHub/Mac/BatteryHubQuickActions.swift` | `testContextMenuActionsExposeSafeImplementedCommandsFirst`, `testContextMenuActionTitlesMatchAirBuddyStyleCommands`, `testAirPodsContextMenuIncludesAudioControls` | Complete |
| Preferences and settings window | `BatteryHub/Mac/BatteryHubSettingsView.swift`, `BatteryHub/Mac/DeviceListPresentation.swift`, `BatteryHub/Mac/BatteryHubHUDView.swift`, `BatteryHub/Mac/BatteryHubQuickActions.swift` | `testBatteryHubSettingsWindowRenderProducesNonBlankImage`, `testBatteryHubSettingsWindowRefreshingRenderProducesNonBlankImage`, settings tab render tests | Complete |
| Battery alerts | `BatteryHub/Mac/LowBatteryNotifier.swift`, `BatteryHub/Mac/BatteryHubHUDView.swift`, settings alert panes | `testLowBatteryNotifierFallsBackToAirPodsPrefixThreshold`, `testChargedAlertRequiresDeviceOptInAndCreatesEventOnceUntilDrained`, `testBatteryHubAlertsCanRenderInitialSelectedDeviceOverrides`, HUD render tests | Complete |
| Shortcuts and automation | `BatteryHub/Mac/BatteryHubAppShortcuts.swift`, `BatteryHub/Mac/BatteryHubQuickActions.swift`, `BatteryHub/Mac/BatteryHubMacApp.swift` | `testBatteryHubAppShortcutsExposeSupportedAutomationActions`, intent bridge tests, app intents metadata extraction in packaged app | Complete |
| Quick actions and keyboard shortcuts | `BatteryHub/Mac/BatteryHubQuickActions.swift`, `BatteryHub/Mac/BatteryHubMacApp.swift`, quick actions settings pane | `testQuickActionPreferencesDefaultToSafeEnabledActions`, `testQuickActionPreferencesRoundTripAndFilterUnsupportedActions`, `testBatteryHubQuickActionsSettingsRenderProducesNonBlankImage` | Complete |
| AirPods audio controls | `BatteryHub/Mac/DeviceListPresentation.swift`, `BatteryHub/Mac/StatusMenuView.swift`, `BatteryHub/Mac/BatteryHubSettingsView.swift` | `testAirPodsAudioPreferencesRoundTripPerDevice`, `testBatteryHubSettingsWindowCanRenderAirPodsAudioControls` | Safe alternative implemented |
| Widget/dashboard glanceability | `BatteryHub/Mac/BatteryHubDesktopWidgetView.swift`, `BatteryHub/Mac/BatteryHubSettingsView.swift`, `BatteryHub/Shared/BatteryHistoryStore.swift` | `testBatteryDesktopWidgetRenderProducesNonBlankImage`, `testBatteryHubDashboardSettingsRenderProducesDesktopWidgetPreview`, history trend tests | Complete |
| Empty/loading/stale/unsupported states | `BatteryHub/Mac/StatusMenuView.swift`, `BatteryHub/Mac/BatteryHubSettingsView.swift`, `BatteryHub/Mac/DeviceBatteryRow.swift`, `BatteryHub/Shared/BatterySnapshotStore.swift` | refreshing render tests, `testUnsupportedBluetoothDeviceStaysVisibleWithoutPercent`, freshness/status render coverage | Complete |
| Preserve existing working behavior | `BatteryHub/Shared/CloudBatterySync.swift`, `BatteryHub/Shared/BatterySnapshotStore.swift`, `BatteryHub/Mac/MacPowerSourceReader.swift`, existing iOS/watch targets | Full current test suite, cloud sync tests, snapshot compatibility tests | Complete |
| Production app folder/build integration | `BatteryHub.xcodeproj/project.pbxproj`, `script/build_and_run.sh`, `script/package_dmg.sh`, new files under `BatteryHub/Mac` and `BatteryHub/Shared` | Xcode build/test/package verification, codesign verify, DMG verify | Complete with signing limits |
| Device transfer / Magic Handoff exclusion | `BatteryHub/Mac/BatteryHubQuickActions.swift` keeps `transferToMac` unsupported and filtered from defaults | `testQuickActionPreferencesDefaultToSafeEnabledActions`, `testQuickActionPreferencesRoundTripAndFilterUnsupportedActions` | Excluded as requested |

## Platform And Product Limits

These limits are intentional, documented, and handled with production-safe
alternatives:

- Direct AirPods listening mode and microphone switching is not implemented with
  private APIs. BatteryHub stores the desired per-device preference, exposes the
  preference in the status/settings UI, and opens macOS Sound or Bluetooth
  Settings for the actual system-level change.
- Real Bluetooth connect/disconnect live testing was not run against the user's
  devices because it would change local device state. The app routes through
  macOS-supported command paths when a paired Bluetooth address is available,
  and tests cover support detection and action selection.
- The scanner degrades into stale, disconnected, and unsupported-device states
  instead of surfacing a hard modal error for normal data-source misses. This is
  deliberate for a menu bar utility where transient Bluetooth/system-profiler
  misses should remain glanceable.
- The local DMG is ad-hoc signed when `DEVELOPER_ID_IDENTITY` is not provided.
  iCloud entitlements are removed when `TEAM_ID` is not provided. Developer ID
  signing, notarization, and final iCloud entitlement restoration require those
  external signing credentials.

## Verification Evidence

Latest evidence from this completion pass:

- `git diff --check` passed.
- `xcodebuild test -project BatteryHub.xcodeproj -scheme BatteryHubMac -destination 'platform=macOS,arch=arm64'` passed with 87 tests and 0 failures.
- `script/package_dmg.sh` built the Release app and produced `dist/BatteryHub.dmg`.
- `codesign --verify --deep --strict --verbose=2 build/dmg-staging/BatteryHubMac.app` passed.
- `hdiutil verify dist/BatteryHub.dmg` reported the DMG checksum as valid.
- App Intents metadata was present in the staged app and included dashboard,
  refresh, low battery, summary, and battery trend actions.
- Render artifacts used for screen inspection:
  - `/tmp/batteryhub-status-menu-render.png`
  - `/tmp/batteryhub-status-menu-refreshing-render.png`
  - `/tmp/batteryhub-settings-refreshing-render.png`
  - `/tmp/batteryhub-airpods-settings-render.png`


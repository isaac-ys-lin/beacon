# Trusted iPhone Lockdown Battery Design

## Goal

Beacon should show battery status for the user's own iPhone without requiring any companion app on the iPhone. It must not create dashboard rows from random BLE advertisements or nearby devices that only happen to look like an iPhone.

The practical route is the same class of solution described by AirBuddy and implemented by AirBattery: use Apple's existing iOS trust and lockdown pairing path. The user connects the iPhone to the Mac once by USB, unlocks it, taps Trust, and Beacon stores that device's UDID in a local allowlist. After that, Beacon may read the iPhone battery through USB or Wi-Fi lockdown when the Mac can reach the same trusted device.

## References

- AirBuddy help: iPhone, iPad, and Apple Watch support requires connecting the device to the Mac with a cable once, trusting the Mac, keeping Wi-Fi enabled, and allowing local network access. It uses the built-in iOS lockdown mechanism and explains that another person's iPhone appears only if it had previously trusted that Mac. <https://support.airbuddy.app/articles/how-can-i-see-the-battery-status-of-my-iphone-in-airbuddy>
- AirBattery project: Mac-only app, no iPhone client app. It asks users to connect iPhone or iPad by USB once and trust the Mac, then reads on the same LAN. <https://lihaoyun6.github.io/airbattery/>
- AirBattery source: uses bundled libimobiledevice tools such as `idevice_id`, `ideviceinfo`, and a `wificonnection` helper to list trusted devices, enable Wi-Fi lockdown, read `com.apple.mobile.battery`, and parse `BatteryCurrentCapacity`. <https://github.com/lihaoyun6/AirBattery>
- libimobiledevice: native iOS device protocol stack, including lockdownd and Wi-Fi sync support. Licenses include LGPL-2.1 and GPL-2.0, so Beacon should avoid copying or bundling GPL command source without a separate packaging decision. <https://github.com/libimobiledevice/libimobiledevice>
- pymobiledevice3: useful protocol reference for iOS services and Wi-Fi connection settings, but GPL-3.0 and Python-based, so it is a reference rather than a shipping dependency. <https://pypi.org/project/pymobiledevice3/>
- BatteryStatusShow: older Swift/C/ObjC reference that also points at libimobiledevice as the relevant family of tools. <https://github.com/sicreative/BatteryStatusShow>

## Non-Goals

- Do not install or require an iPhone app.
- Do not use BLE iPhone display names as device identity.
- Do not add a row for an iPhone unless its UDID is in Beacon's trusted iPhone allowlist.
- Do not silently enable Wi-Fi sync on the iPhone in the first implementation.
- Do not bundle AirBattery source code or copy GPL implementation code.
- Do not replace the current Bluetooth keyboard, mouse, trackpad, or AirPods pipeline.

## Approach

Beacon gets a new iOS lockdown provider that is separate from the current Bluetooth scanner concerns:

1. `TrustedIPhoneRegistry` owns the local allowlist of iOS UDIDs that the user explicitly added.
2. `IPhoneLockdownBatteryProvider` discovers `idevice_id` and `ideviceinfo` command-line tools, lists USB and network lockdown devices, reads `DeviceName`, reads `com.apple.mobile.battery`, and emits candidates only for allowlisted UDIDs.
3. `BluetoothDeviceScanner.connectedCandidateReport` still merges local HID, system profiler, and BLE Battery Service candidates, then adds trusted iPhone candidates from the lockdown provider.
4. `BluetoothBatteryResolver.report` drops BLE iPhone candidates before snapshots are created. That keeps random or stale iPhone BLE readings from becoming Beacon rows.
5. Settings adds an iPhone setup card. The user connects a phone by USB, unlocks it, taps Trust, and clicks an explicit Beacon action to add the connected trusted iPhone. The app saves the UDID locally.
6. Settings also exposes a Forget action for trusted iPhones. Forgetting removes the Beacon allowlist entry and the local Beacon snapshot, but does not unpair the iPhone from macOS.

The first implementation may depend on external libimobiledevice CLI tools installed on the Mac. If tools are missing, Beacon reports a diagnostic row and points the user to install them. A separate packaging pass can decide whether to ship a signed helper or bundled libraries.

## Data Model

Add:

- `TrustedIPhone`: `udid`, `displayName`, `trustedAt`.
- `TrustedIPhoneRegistry`: loads and saves `[TrustedIPhone]` in UserDefaults.
- `IPhoneLockdownConnection`: `usb` or `network`.
- `IPhoneLockdownDevice`: UDID, display name, battery percent, charge state, and connection type.

Snapshot IDs for trusted iPhones use the UDID, not display name:

```swift
trusted-iphone-00008110-001234567890801E
```

That prevents duplicate rows for the same phone across USB and Wi-Fi, and it prevents two phones with the same display name from collapsing into one row.

## UI Behavior

The existing Add Device sheet gets an iPhone row:

- Title: `iPhone or iPad`
- Subtitle: `Connect by USB, unlock, Trust this Mac, then add it here.`
- Action: `Trust`

When the user clicks Trust, Beacon lists USB lockdown devices and reads each device name. If one or more trusted USB devices are visible, it adds them to `TrustedIPhoneRegistry`, refreshes battery data, and keeps the Settings window on the Devices pane. If no device is visible, Settings shows the latest enrollment result: command missing, no USB iPhone, device not trusted, or device added.

For trusted iPhone rows in the device inspector:

- Source label is `Trusted iPhone`.
- Stale/expired behavior uses the existing freshness UI.
- A `Forget this iPhone` button removes the allowlist entry.
- Explanatory copy states that forgetting in Beacon does not remove the macOS trust pairing.

## Diagnostics

`BatteryRefreshDiagnostics` already records provider attempts. The new provider uses the existing diagnostics shape:

- `provider: .ideviceInfo`
- `status: .reported` when at least one allowlisted iPhone reports battery.
- `status: .commandMissing` when `idevice_id` or `ideviceinfo` is absent.
- `status: .noReport` when devices exist but none are allowlisted or no battery payload was returned.
- `status: .timedOut` when a command exceeds the timeout.
- `message` includes USB/network counts and allowlist filtering counts.

Settings should pass `latestRefreshDiagnostics` into `BeaconSettingsView` and render a compact diagnostics card in the Devices pane. This closes the current gap where diagnostics exist in the model but are not visible in Settings.

## Testing

Use test-injected command runners so unit tests do not require a real iPhone or real libimobiledevice install.

Required tests:

- `TrustedIPhoneRegistry` round-trips through isolated `UserDefaults`.
- Registry trust updates display name without duplicating UDIDs.
- Lockdown parser reads `BatteryCurrentCapacity`, `BatteryIsCharging`, and `DeviceName`.
- Provider lists USB and network devices, but emits snapshots only for allowlisted UDIDs.
- Provider reports `commandMissing` when either `idevice_id` or `ideviceinfo` is missing.
- Resolver drops BLE iPhone candidates.
- Trusted iPhone snapshots use UDID-based IDs and high confidence.
- Battery provider label changes from `USB iPhone` to `Trusted iPhone`.
- Add Device guide renders an iPhone setup row.
- Settings can render diagnostics.

Manual verification:

1. Install libimobiledevice tools on the Mac used for testing.
2. Connect the user's iPhone by USB, unlock it, and trust the Mac.
3. Confirm `idevice_id -l` returns the iPhone UDID.
4. Add the iPhone in Beacon Settings.
5. Confirm `/Applications/BeaconMac.app` is the running app.
6. Confirm the iPhone row appears only after allowlisting.
7. Confirm a fake or nearby BLE iPhone does not create a row.

## Risks

- A sandboxed app may not be able to launch external Homebrew tools in all signing modes. The implementation must verify this in the installed `/Applications/BeaconMac.app`, not only in tests.
- Wi-Fi lockdown availability depends on iPhone trust, Finder Wi-Fi sync state, network reachability, and local network permissions. The UI must present stale data honestly.
- Bundling libimobiledevice command-line tools introduces license, signing, notarization, and helper lifecycle work. That is intentionally out of scope for the first pass.

## Spec Self-Review

- Scope is focused on one subsystem: trusted iOS lockdown battery reading.
- The design explicitly excludes iPhone companion apps and BLE identity guessing.
- Identity uses UDID, not display name, which fixes same-name phone collisions.
- Diagnostics are visible in Settings, so command and trust failures are actionable.
- Packaging/bundled helper decisions are documented as risks, not hidden implementation requirements.

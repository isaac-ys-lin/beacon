# Headphone connections — issue #5

This describes the implementation and required evidence, not physical acceptance.
Parent spec #1 and the current ticket/comments remain authoritative.

## Behavior

Paired Bluetooth identities appear in the existing menu/inspector without needing
a battery report. Missing battery values and timestamps stay missing; these
inventory entries are presentation-only, never battery-history records. Pin/hide
preferences remain intact. Reconnection does not promote a disconnected battery
report to a new reading.

Connect, Disconnect, Use for Audio, Check Result and retry share one coordinator.
Shortcuts use the same path and expose the result in the existing menu. A true
return means only that work started. Success requires two consecutive independent
observations of the actual link and, for audio/video or unclassified accessories,
the default Core Audio output. Disconnect requires two disconnected observations.
An accepted command or output-selection request is never sufficient. Results are
labeled as historical operations, not perpetual current connection state.

Addresses, not names, select targets. Same-name/renamed devices remain distinct.
Missing/ambiguous identities, rejection, permission errors, timeout and a link
that drops before confirmation remain failures with retry/check/settings recovery.
A vanished pairing retains its operation entry without asserting current pairing.

## Native boundary

The public IOBluetooth asynchronous connect overload is used with a retained
callback target. Its immediate return acknowledges a command; callback errors,
actual isConnected state and Core Audio output readback are separate evidence.

Core Audio mapping is deliberately conservative: a complete Bluetooth address UID,
optionally ending in :output, must have Bluetooth/LE transport, a live device and
output streams. Selection requires a unique eligible output. Unknown UID formats
or ambiguity remain audio-unverified, never matched by display name. The default
output is read independently after selection. No headphone model or UID convention
has been validated on physical hardware here. Default-output selection also does
not prove audible playback in an app with its own explicitly selected output.

Apple primary API references:
- https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/openconnection(_:withpagetimeout:authenticationrequired:)
- https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice

No listening-mode hardware control or cross-Mac HID transfer is introduced.
Reference mode preferences/settings are not mode-switch success.

## Automated evidence

BeaconMac tests cover no-battery eligibility/hiding, accepted-but-unconfirmed
commands, transient output matches, drops, disconnect outcomes, same-name/renamed
identity, rejected/denied requests, ambiguity/lost pairing, retained recovery,
late-result checking without another command, concurrent operations, stale battery
preservation and strict audio identity parsing. BeaconMacUI exercises menu and
inspector controls with the existing DEBUG preview seam and records screenshots
explicitly labeled fixture-not-hardware. The fixture makes no Bluetooth/Core Audio
calls or battery-history writes. Existing CI and schemes are unchanged; record
exact PR head, synthetic tested commit, xcresult summaries and artifact hashes.
Linux syntax parsing is not macOS compilation or runtime evidence.

## Remaining physical acceptance — keep #5 open

The authorized desktop connector returned No devices available. The local editor
has Linux/Swift but no Xcode or paired headphones. macOS CI is a software runner,
not a real-device test bench. No physical connection, output or audible test was
performed in this session.

Smallest unblock: connect an authorized Mac with paired headphones and permit a
controlled connect/disconnect and audible-output test. Record commit/version, Mac
model, macOS, headphone model/firmware, sanitized stable identity, before/after
Bluetooth and default-output readings, independent audible playback, callback
errors, times and screenshots/logs. Cover no-battery discovery, duplicate names or
rename, rejection/permission, timeout, drop, disconnect, retry and unknown UID
formats. Restore the original output afterwards. Do not post credentials or raw
personal device identifiers. Keep #6/#7/#9 hardware-mode work separately blocked.

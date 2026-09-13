# Distribution verification — independent implementation for #13

Parent #1, #13 and their current dependencies remain authoritative. This is a
runbook, not an acceptance record. No credentialed signing, notarization,
Gatekeeper assessment, installation, relogin or clean-Mac test was performed here.
Do not close #13 or describe the app as release-ready.

## Existing packaging path, fail-closed evidence

Use `script/package_dmg.sh` and the existing `BeaconMac` Release scheme. Local
ad-hoc packaging remains available without credentials; it explicitly says that
distribution and installation have not been verified. Architecture remains arm64,
matching the existing script. No Intel compatibility claim is added.

Formal packaging requires a clean reviewed checkout, a Developer ID Application
identity in the signing Mac's keychain and an explicitly expected signing team:

```sh
NOTARIZE=1 CONFIGURATION=Release \
DEVELOPER_ID_IDENTITY='Developer ID Application: YOUR NAME (YOURTEAMID)' \
EXPECTED_TEAM_ID='YOURTEAMID' NOTARY_PROFILE='your-existing-keychain-profile' \
script/package_dmg.sh
```

Use an existing local keychain profile, never paste credentials into an issue/PR.
The legacy Apple ID/app-specific-password/team environment-variable path remains
supported. Required inputs are validated before builds or removal of an old
package, and their values are not printed.

The staging copy is stamped with the full source commit before signing. Actual
certificate/team, secure timestamp, hardened runtime, release entitlements,
bundle identity/version/build/executable are checked. A new nested-code layout
fails closed rather than deep-signing helpers with the app's entitlements. If
frameworks/helpers are added later, review their inside-out signing policy first.

The DMG is signed before submission. Apple's JSON response and log are retained;
only exact `Accepted` status with a valid submission ID permits stapling. Command
acceptance alone is not completion. The independent final verifier checks the
immutable DMG's signature, ticket, enabled Gatekeeper, image integrity, read-only
mount and the app inside that image. It never installs, launches, strips
quarantine, disables Gatekeeper or force-detaches a volume.

Sidecars beside the DMG:
- `.notary.json` and `.notary-log.json`: Apple's actual response and log.
- `.verification.json`: final DMG SHA-256/size, app version/build/team/source commit
  and security checks. Runtime, real-device, clean-Mac, permissions, relogin and
  upgrade fields remain `not_performed`; release acceptance is `not_assessed`.
  Old sidecars are removed before replacement so a failed build cannot inherit
  a prior passing report.

Recheck an actual package on macOS without installing it:

```sh
python3 script/release_checks.py artifact /path/to/Beacon.dmg \
  --team YOURTEAMID --output /path/to/new-verification.json
```

Existing output files are refused. Failed checks exit nonzero without a passing
report. Retain failed logs and source revision separately. Security checks do not
prove the actual download route or installation UX.

## Automated tests are not distribution evidence

Run `python3 -m unittest -v test_release_checks.py` from `script/`. Temporary files
and injected Apple command responses cover 14 cases: accepted/rejected/malformed
responses, credentials, certificate/team/timestamp/runtime, debug entitlements,
changed code layout, disabled Gatekeeper, stale evidence, failed ticket/image/app
checks, mount cleanup and changed hashes. The existing BeaconMac scheme runs the
same suite through `ReleaseScriptTests`. No real signing or Apple network calls
occur. A passing test is not a signed or notarized app.

## Exact blockers and smallest unblock

Desktop Commander reported **No devices available**. The local editor is Linux
without Xcode; hosted CI is not a signing keychain or clean receiving Mac. No
Developer ID identity, expected team or authorized notary profile was supplied.
#12 and the hardware-mode chain remain incomplete. No credentials are guessed.

After review/merge, execute formal packaging on an authorized signing Mac using
its existing credentials. Record reviewed source, command exits, Apple submission
ID, logs and final stapled DMG hash. Then test the actual intended download route
on a separate clean Mac/user with Gatekeeper enabled and quarantine intact.
Record Mac model, architecture, macOS, browser/download source, version and hash.

| Acceptance | Independent observation required | Current result |
| --- | --- | --- |
| Download/install | Download, open DMG, copy app, launch without bypass | Not performed |
| First setup | Clear next step, empty devices, permission denial/recovery | Not performed |
| Missing tools | Basic Mac/Bluetooth usable; truthful iPhone tool guidance | Not performed |
| Login launch | Register, sign out/in, observe actual launch and recovery | Not performed |
| Upgrade | Preferences retained, correct version, manual download/support | Not performed |
| Hardware | Bluetooth, audible output and supported physical mode changes | Not performed |
| Accessibility | Actual keyboard/VoiceOver, languages, appearance, screens | Not performed |

Stop at failures, preserve evidence and leave criteria open. No release upload,
automatic updater, credentials, public artifact, issue closure or merge is added.

Primary references, reviewed 2026-09-13:
- https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- https://developer.apple.com/documentation/security/resolving-common-notarization-issues
- https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/
- https://developer.apple.com/library/archive/technotes/tn2206/_index.html

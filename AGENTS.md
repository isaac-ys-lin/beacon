# AirBuddy Project Guidance

## Scope

- This is a macOS app whose production scheme is `BeaconMac`.

## Skill routing

- Use `$build-macos-apps:build-run-debug` for builds, tests, launches, logs, and runtime debugging.
- Use `$build-macos-apps:window-management` for window and scene behavior, and `$build-macos-apps:appkit-interop` only for a narrow AppKit bridge.
- Use `$build-macos-apps:swiftui-patterns` or `$build-macos-apps:view-refactor` only for relevant SwiftUI work.
- Use `$build-macos-apps:signing-entitlements` or `$build-macos-apps:packaging-notarization` only for signing, Gatekeeper, archive, DMG, or release work.
- Load only task-relevant skills.

## Verification

- Prefer `script/build_and_run.sh` for the normal app path and `script/package_dmg.sh` for packaging work.
- Keep local build, runtime, signing, package, and notarization evidence distinct.

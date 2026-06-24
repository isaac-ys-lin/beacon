# iPhone Battery Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make iPhone battery readings reliable, diagnosable, and honest in the BatteryHub UI.

**Architecture:** Split raw battery collection from snapshot presentation by adding provider metadata, diagnostics, iPhone identity normalization, and a safe optional USB fallback path. Keep CoreBluetooth as the primary path and report why a refresh is stale instead of implying hotspot-based readings.

**Tech Stack:** Swift, SwiftUI, CoreBluetooth, IOKit, UserDefaults, XCTest, optional `ideviceinfo` command discovery.

**Status:** Completed 2026-06-24. Verified with full `BatteryHubMac` test suite and app build.

---

### Task 1: Provider Metadata and iPhone Identity

**Files:**
- Modify: `BatteryHub/Shared/BatterySnapshot.swift`
- Modify: `BatteryHub/Mac/BluetoothBatteryResolver.swift`
- Modify: `BatteryHub/Shared/BatterySnapshotStore.swift`
- Test: `BatteryHubTests/BluetoothBatteryResolverTests.swift`
- Test: `BatteryHubTests/BatterySnapshotStoreTests.swift`

- [x] Add snapshot metadata for provider, confidence, and latest attempt state.
- [x] Classify BLE names containing iPhone as `.iPhone`.
- [x] Normalize BLE iPhone IDs by stable display name so UUID churn does not duplicate the same phone.
- [x] Add tests for iPhone classification, metadata defaults, and UUID churn merge.

### Task 2: Refresh Diagnostics

**Files:**
- Modify: `BatteryHub/Shared/BatterySnapshot.swift`
- Modify: `BatteryHub/Mac/BluetoothDeviceScanner.swift`
- Modify: `BatteryHub/Mac/BluetoothBatteryResolver.swift`
- Modify: `BatteryHub/Mac/BatteryHubMacApp.swift`
- Test: `BatteryHubTests/BluetoothBatteryResolverTests.swift`

- [x] Track provider attempts for local HID, system profiler, BLE, and optional USB.
- [x] Preserve latest diagnostics on `BatteryHubModel`.
- [x] Expose diagnostics to settings support views without changing refresh behavior.

### Task 3: UX Honesty for Stale iPhone Data

**Files:**
- Modify: `BatteryHub/Mac/DeviceBatteryRow.swift`
- Modify: `BatteryHub/Mac/BatteryHubSettingsSupportViews.swift`
- Test: `BatteryHubTests/DeviceListPresentationTests.swift`

- [x] Show source labels that distinguish Bluetooth Battery Service from hotspot/Wi-Fi.
- [x] Show last updated relative text for stale/expired device rows.
- [x] Keep current compact layout and avoid crowding the status popover.

### Task 4: Optional USB Fallback

**Files:**
- Modify: `BatteryHub/Mac/BluetoothBatteryResolver.swift`
- Modify: `BatteryHub/Mac/BluetoothDeviceScanner.swift`
- Test: `BatteryHubTests/BluetoothBatteryResolverTests.swift`

- [x] Add a safe optional `ideviceinfo` parser for `BatteryCurrentCapacity`.
- [x] Only run the provider when `ideviceinfo` is installed.
- [x] Report missing command as diagnostics, not as an app error.

### Task 5: Verification

**Files:**
- Build/test only.

- [x] Run the targeted test suite.
- [x] Run the macOS build.
- [x] Inspect the final diff for unrelated changes.

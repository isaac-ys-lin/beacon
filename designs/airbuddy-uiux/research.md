# BatteryHub UIUX Direction

## Goal

Design a high-fidelity UI/UX direction for the existing BatteryHub macOS menu bar app, using AirBuddy as the quality benchmark for polish, clarity, and native-feeling utility.

## Fresh Reference Notes

- Official AirBuddy site: the product centers on an AirPods-style status HUD, menu bar battery overview, quick actions, battery alerts, Shortcuts, and Magic Handoff.
- Official screenshot assets captured locally:
  - `assets/airbuddy-platter-large.png`
  - `assets/airbuddy-menu-bar-light.png`
- Additional public review screenshots show AirBuddy 2 using grouped device rows, dark/light popover variants, settings panes, and widget-style battery surfaces.

## Local Product Context

- Existing app is a SwiftUI `MenuBarExtra` utility.
- Current UI files reviewed:
  - `BatteryHub/Mac/StatusMenuView.swift`
  - `BatteryHub/Mac/DeviceBatteryRow.swift`
  - `BatteryHub/Shared/DesignTokens.swift`
  - `BatteryHub/Mac/DeviceListPresentation.swift`
- Current data model already supports grouped Mac/peripheral and mobile/audio sections, AirPods component aggregation, freshness, charging state, critical low battery state, refresh, and low-battery settings.

## Design Thesis

BatteryHub should feel like a calm Apple-native control surface:

- Fast glance first: percentages, charging, stale data, and critical states must be readable in under a second.
- Spatial hierarchy: the Mac and its peripherals belong together; mobile/audio devices belong together; AirPods component detail should be visible without making every row noisy.
- Light polish, not marketing: use vibrancy, precise spacing, native glyph language, and restraint. Avoid dashboard bulk.
- Action on hover/click: each row should expose only the next useful action, such as pin, alert, refresh, handoff, connect, or details.

## Proposed UX Structure

1. Menu bar popover as the primary surface.
2. AirPods/HUD status as the delightful quick-connect surface.
3. Alert configuration as a small contextual flow, not a full settings wall.
4. Settings as a compact inspector with sync freshness and notification thresholds.

## Prototype Scope

The prototype in `BatteryHub UIUX Prototype.html` explores:

- Light and dark glass popover variants.
- Device list with grouped cards, status chips, charging/low/stale states.
- AirPods detailed row and HUD.
- Contextual settings/alerts panel.
- In-page controls for variant, theme, density, and active screen.


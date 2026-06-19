# BatteryHub Icon Direction

The current direction is monochrome, SF Symbols-first, and runtime-safe.

Chosen symbols:

- `antenna.radiowaves.left.and.right`: primary menu bar and Bluetooth entry mark.
- `dot.radiowaves.left.and.right`: alternate compact wireless mark.
- `minus.plus.batteryblock`: BatteryHub brand direction for future app icon work.
- `keyboard`: Keychron and keyboard device glyph.

Rejected directions:

- Hand-drawn Bluetooth rune: too crude and too far from native macOS.
- Multi-detail battery/wireless composites at menu-bar size: too noisy below 24 px.
- Keyboard as the app logo: too specific, makes BatteryHub read as keyboard-only.

Render the local candidate sheet:

```sh
swift designs/batteryhub-icons/render-sf-candidates.swift designs/batteryhub-icons/sf-symbol-candidates.png
```

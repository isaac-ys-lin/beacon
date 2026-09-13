# Connection HUD — issue #8

Depends on the connection implementation in #5. The HUD observes real coordinator
operations from all existing entry points; it never converts command acceptance
or a stored preference into a hardware result. Mode control (#6/#7/#9) is not added.

Operations preempt (but retain) battery reminders. Updates coalesce only for the
same operation UUID; different devices/results wait in order, even with identical
names. Late battery events cannot overwrite pending operations or a terminal
result's display interval. Every event in an alert batch is considered, rather
than dropping all but its first entry. Closing progress does not cancel Bluetooth
and does not suppress its later terminal result.

Pending progress remains until the bounded coordinator completes. Terminal results
respect global HUD, auto-dismiss/delay and visible-dismiss preferences. Recovery
opens the original device inspector only on explicit Review Result; displaying a
production HUD does not activate the app or take keyboard focus. Turning HUD off
clears its display/queue, not connection state. Original menu/inspector results
remain available even with HUD disabled.

A cancelled timer now exits, and each timer owns a presentation generation; an
old timer cannot dismiss a replacement HUD that reuses the same NSPanel.

## Software evidence, not physical acceptance

BeaconMac tests cover late-battery ordering, multiple same-name operations,
dismissed progress followed by its result, real nonactivating NSPanel properties,
old-timer cancellation, a full terminal-result interval, persistent/manual and
global-disabled preferences. BeaconMacUI drives the separate HUD (not the Settings
preview) and routes its unconfirmed result to the exact same-name inspector.
The existing accessibility-only window adapter is used solely by UI automation;
non-focus behavior is independently checked on the production NSPanel in unit
coverage. These are injected Bluetooth/audio observations, not physical evidence.

Keep #8 open until #5's real headphone flow and this HUD are jointly exercised on
an authorized Mac. Record exact commit/app version, macOS/headphone model, focus
before/after, screenshots, real failure/success and later battery events. Also
verify multiple displays, keyboard/VoiceOver, reduced motion and contrast under
#12. No signing/notarization or clean-Mac acceptance is claimed here.

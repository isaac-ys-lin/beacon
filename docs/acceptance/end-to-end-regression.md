# End-to-end regression evidence — issue #12

This is an implementation/coverage map, not an acceptance record. Parent #1 and
all current ticket criteria/dependencies remain unchanged. Keep #12 open until
its hardware, mode, notification, accessibility and integrated checks are met.

## Added independent regression paths

The existing BeaconMac/BeaconMacUI schemes and CI remain the entry points.
`AcceptanceSurfaceUITests` launches the actual app with the existing process-level
preview seam. It does not replace the app with a settings-preview view.

- Native `NSSavePanel`: cancel returns without a success message or file; a later
  explicit Save through Go to Folder writes a readable CSV with the real export
  schema, then and only then presents the export result. The file is in a unique
  temporary test directory and removed afterwards. No injected output URL or
  bypassed save dialog is used.
- Keyboard: Command-W closes the actual settings window. Existing Escape tests
  for the menu and setup sheets are retained.
- Actual desktop widget: compact and expanded independent native windows expose
  truthful no-report state and route their own Settings button to Dashboard.
  This is not the noninteractive Dashboard sample preview.
- The four English/Traditional-Chinese × light/dark scenarios now visit all six
  settings pages at the supported 900×620 content minimum, retaining prior
  control, label, no-cross-Mac and preview-provenance assertions.

The desktop-window adapter is DEBUG-only and mirrors the existing HUD/menu AX
adapter: title/activation changes permit XCTest to inspect the actual panel.
Production remains borderless/nonactivating. Window frame saves use a test-only
name; widget visibility/style and appearance are launch-argument overrides, not
persisted changes to normal user settings. The adapter does **not** prove that
production never steals focus. Existing production AppKit window/geometry tests
remain, and real focus/multi-screen/Space acceptance is separate.

No passing macOS execution is claimed by syntax checks. New screenshots are named
`fixture-not-hardware`; all existing preview-process tests likewise use synthetic
input. CSV content is checked as an export, not as physical battery evidence.

## What must be recorded for each run

Preserve the PR head **and** actual tested synthetic merge commit, app version and
build, Xcode/macOS/architecture, exact scheme/command, unit/UI counts including
failures and skips, run/job URLs, xcresult and screenshot attachment paths and
artifact SHA-256. The existing CI records environment/source and both result
bundles. An empty, skipped, cancelled or failed run is not a pass. A rerun must
remain associated with its own attempt and tested commit.

For manual runs, separately record operator, Mac model, macOS, languages, display
sizes/scales, monitor arrangement, app/version/commit, physical device model and
firmware (where applicable), exact action, expected state, observed state, evidence
path and whether the scenario passed, failed, was blocked or not run. Sanitise
personal identifiers. No blank cell should be interpreted as a pass.

## Integrated acceptance matrix (not performed unless separately evidenced)

| Area | Software evidence available | Still required |
| --- | --- | --- |
| Menu and setup | Existing app-process empty/denied/recovery/Escape tests | Real first launch, permission and zero-device recovery (#2) |
| iPhone | Existing preflight, report and retry fixtures | Real USB trust/tools/no-report results (#3) |
| Battery truth | Existing fresh/stale/disconnected/missing/failure identity tests | Physical states and actual timestamps (#4) |
| Headphone controls | Separate #5 PR tests, not part of this main-based PR | Physical paired/no-battery connection, independent audio output/audible playback |
| Headphone mode | No hardware implementation verified | Feasibility/readback #6, actual controls #7 and mode HUD #9 |
| Connection HUD | Separate #8 implementation/tests | Integrate reviewed #5/#8 and observe physical result/recovery ordering |
| Settings | Six native panes × 2 languages × 2 appearances at minimum size | Keyboard traversal/activation of every relevant control; real VoiceOver order/value/action |
| Desktop | Both actual native sizes, navigation; existing geometry unit tests | Multiple real screens/scales, unplugging, Spaces/fullscreen, background focus |
| Notifications | Existing permission/result state tests | Real system banner/list and denied/delivery failure recovery; API enqueue is not delivery |
| History/export | Real Save/Cancel UI and readable CSV | Long-lived physical history and realistic upgrade data |
| Login/support | Existing visible status/recovery/support tests | Investigate actual Unavailable cases and signed registration/relogin (#11/#13) |
| Accessibility | AX labels/actions and window tests | Actual VoiceOver, full keyboard traversal, increased contrast, reduced motion and real screen clipping |
| Distribution | Separate #13 fail-closed tool tests | Developer ID, notarization, Gatekeeper and separate clean receiving Mac |

A settings screenshot is not a notification, actual mode transition or desktop
window test. A simulator/fixture screenshot is not real-device proof. Do not
substitute these artifacts for missing rows.

## Blocker and smallest unblock

The authorized desktop connector returned `No devices available`; the local
editor has Linux/Swift syntax parsing but no Xcode, attached devices or a macOS
accessibility session. Hosted macOS CI can execute software regression but cannot
establish the physical model/firmware, audible output, user permissions, VoiceOver
experience or separate clean installation. #12's native dependencies remain open.

Connect one authorized Mac with the intended paired headphones/iPhone and relevant
screens, review/merge the prerequisite PRs, then execute each outstanding matrix
row and retain independent evidence. Hardware mode work starts only after #6
actually demonstrates a change and read-back. A separate signing/clean receiving
Mac exercise remains #13. No issues or PRs are closed or merged by this work.

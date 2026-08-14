# Beacon 可靠性與原生體驗優化

Status: 實作完成；本機 UI automation runtime verification 受系統認證阻擋
Last updated: 2026-08-14

## Goal

在不增加新產品線、服務或外部依賴的前提下，讓 Beacon 的電量刷新可以局部成功、資料合併可預測、通知只採用可信資料，並補齊失敗復原、macOS 視窗禮儀、accessibility 與可維護性。

## Current contract

- In scope:
  - 隔離 IORegistry、`system_profiler`、CoreBluetooth、`ideviceinfo` provider；單一 timeout 不得丟棄其他已完成結果。
  - 建立 deterministic candidate identity/merge policy，避免 disconnected 或較弱來源覆蓋 connected/較可信結果。
  - 通知只採用 fresh、connected snapshot；Unified Log 不公開裝置名稱、ID/MAC 或百分比。
  - 將既有 `BatteryRefreshDiagnostics` 接到 Settings，補齊 Bluetooth 配件與 iPhone 的實際 onboarding。
  - 修正 HUD 搶焦點、Settings 固定內容卻可 resize、widget 不記住位置、Escape/VoiceOver/selection 語意缺口。
  - 讓 XcodeGen、unit/UI smoke 與 `.xcresult` verifier 真正覆蓋 production scheme；大型拆檔另案處理。
- Out of scope:
  - 不重做現有視覺語言、status panel、Settings 五 pane、widget、HUD、Shortcuts、AirPods controls、pin/hide 或空狀態。
  - 不恢復 Mac 本機電量列、iOS/watch/iCloud companion、Magic Handoff/device transfer 或 private AirPods API。
  - 不在本變更導入 trusted-iPhone UDID allowlist；舊 spec 與 live code 對此互相矛盾，需另作產品決策。
  - 不變更 45 秒輪詢頻率；先以 provider duration telemetry 取得能源與延遲證據，再另案判斷 backoff。
  - 不做 Liquid Glass、SwiftPM、Developer ID、DMG、公證或 App Store 工作。
- Acceptance:
  - `ideviceinfo` 或任一 provider timeout 時，其他已完成的裝置仍更新；timeout 只標在正確 provider。
  - 同輪資料以欄位級規則合併；不同 strong ID 的非 iPhone 裝置不因同名被合併，未完成 provider 不得觸發誤刪。
  - stale、expired、disconnected snapshot 不產生 low/charged event，恢復 fresh 後仍只通知一次。
  - Settings 能把每個 provider 結果翻成白話原因與下一步，且不暴露原始 command output。
  - HUD 出現不改變其他 app 的 key window/first responder；Settings/widget 位置與尺寸符合原生 macOS 預期。
  - 所有既有功能仍可用，full test、render smoke、runtime/manual checks 全部通過；完成只代表 merge-ready / local-runtime-ready，不代表 distribution-ready。

## Decisions

- **Confirmed** — production scheme 是 `BeaconMac`；`project.yml` 是 Xcode target/scheme 的 source of truth。
- **Confirmed** — app 維持 macOS 14+、`LSUIElement`、non-sandboxed direct-download 架構；特殊 panel 繼續使用集中、窄範圍 AppKit bridge。
- **Confirmed** — 現有視覺方向與已完成 surfaces 保留；本次不以重畫 UI 取代資料可靠性修正。
- **Confirmed** — 使用者於 2026-08-14 核准完整計畫；依「可信刷新 → 可復原 UX → 視窗/AX → verifier」排序。
- **Confirmed** — Phase 1 不宣稱可判定 USB-name 與 BLE UUID 是否屬於同一支 iPhone；維持現有 single-iPhone consolidation 邊界，但把 winner 改成 deterministic（connected、有 percent、USB 優先）。多 iPhone 與 trusted UDID binding 另案決策。
- **Confirmed** — macOS UI test runner 必須以 test-only ad-hoc signing 啟動；CI 維持非零 tests／零 failures 的 fail-closed gate，並以 10 分鐘 step timeout 避免 testmanagerd 卡住整個 job。
- **Superseded** — 三份舊計畫只作歷史證據；本檔在實作結束後歸檔為本輪唯一 final-state authority。

## Implementation phases

每個 phase 都可獨立合併；後續 phase 未執行時，app 仍維持可用狀態。

### Phase 1 — 可信刷新、合併與通知邊界

Files:

- Create `Beacon/Mac/BatteryProviderRunner.swift`：以 internal process factory / lifecycle callback 建立可測試 seam；stdout/stderr 並行 drain，透過 `Process.terminationHandler` 回收，timeout/cancel 競態只完成一次。收到 cancel 後先送 SIGTERM、最多等 250ms，再送 SIGKILL；不得用無期限 `waitUntilExit()`。
- Modify `Beacon/Mac/BluetoothDeviceScanner.swift`：用 task-group outcome collector 跑 provider，共用一個 absolute `ContinuousClock.Instant`（8 秒）；每個 subprocess 只使用剩餘時間。deadline 後取消未完成 child，等 bounded kill/reap 完成再回傳 partial report；BLE/IORegistry 加 cooperative cancellation。
- Modify `Beacon/Mac/BluetoothDeviceScanner.swift` / `Beacon/Mac/BluetoothBatteryResolver.swift`：`system_profiler` 與 `ideviceinfo` 都改用 runner；每個 provider outcome 明列 `provider/status/candidates/attemptedAt`，report 同時攜帶 authoritative completed provider set。
- Modify `Beacon/Mac/BeaconMacApp.swift`：移除外層 all-or-nothing timeout，永遠接收 partial report。
- Modify `Beacon/Shared/BatterySnapshotStore.swift`：改為 provider-aware reconciliation。只有本輪完成為 `.reported` / `.noReport` 的 provider 可以 prune 自己未再回報的 snapshot；`.timedOut/.unavailable/.unauthorized/.commandMissing` 一律保留舊值與原 timestamp。Scanner 負責同輪 merge，Store 只負責跨輪 chronology/prune。
- Modify `Beacon/Mac/BluetoothBatteryResolver.swift`：`BluetoothBatteryCandidate` 加入 explicit identity evidence，而非從格式猜測強度。
- Modify `Beacon/Mac/LowBatteryNotifier.swift`：authoritative API 接受 `DecoratedBatterySnapshot` 與顯式 `now`；stale/expired/disconnected 在任何 alias/latch/UserDefaults mutation 前返回。stale 期間不 reset 已通知 latch；恢復 fresh 且仍低電量不重複，只有 fresh recovery 越過門檻才 reset。
- Modify `Beacon/Mac/LowBatteryNotifier.swift`、`Beacon/Mac/BeaconHUDController.swift`：info log 僅保留 event kind/count/duration；名稱、ID/MAC/UUID、notification request ID、百分比一律 private 或不記錄。
- Add provider start/end `OSSignposter` spans，不擴充 diagnostics schema；輪詢頻率的後續判斷只採用實測 duration/energy evidence。
- Test `BeaconTests/BatteryProviderRunnerTests.swift`、`BeaconTests/BluetoothBatteryResolverTests.swift`、`BeaconTests/BatterySnapshotStoreTests.swift`、`BeaconTests/LowBatteryNotifierTests.swift`。

Identity evidence:

| Transport | Identity evidence | Strength | Merge boundary |
|---|---|---:|---|
| HID / IORegistry | `PhysicalDeviceUniqueID`、device/Bluetooth address、serial | strong | exact strong ID 才直接合併；name fallback 是 synthetic |
| `system_profiler` | `device_address` | strong | 缺 address 時 name 是 synthetic |
| CoreBluetooth | `CBPeripheral.identifier` | medium | 只在本機穩定；不可推論為硬體地址 |
| USB iPhone（本輪現況） | normalized display name | synthetic | 不宣稱能與 BLE UUID 建立可信 binding |
| Unknown/name fallback | normalized name + kind | synthetic | 僅能併入同輪唯一、無 strong-ID 衝突的 cluster |

Same-refresh field merge:

| Field | Rule |
|---|---|
| canonical identity | 取 cluster 內最強 evidence；兩個不同 strong ID 永不因同名合併 |
| display name / kind | 先排除 generic name，再取 connected、較高 provider rank 的同輪值 |
| connection | explicit connected > explicit disconnected > unknown；若有 connected candidate，percent/charge 不可取 disconnected candidate |
| percent | eligible connected candidates 中 non-nil 優先，再依 `usb > hid > systemProfiler > classic > ble > unknown` |
| chargeState | eligible、同輪 explicit value > unknown；不從舊 refresh 沿用 `.charging/.full` |
| source/provider/confidence | 跟隨 percent winner；無 percent 時跟隨 connection winner |
| updatedAt | 只在 provider 本輪實際觀測時更新；因 provider 失敗而保留的舊 snapshot 不改時間 |

上述 provider rank 只作用於同一 refresh；跨 refresh 只看 chronology、freshness 與 provider completion，不再做第二套欄位 precedence。

Required tests:

- hung `ideviceinfo` 仍回傳 HID/AirPods partial success，且 diagnostics 同時保留 completed 與 timed-out outcomes。
- runner fixture 產生大量 stdout/stderr 且忽略 SIGTERM 時仍不 deadlock；deadline 後 PID 不存在，completion 只發生一次。
- BLE timeout + HID success 保留先前 BLE mouse；profiler timeout + HID success 保留先前 AirPods；authoritative `noReport` 才能 prune 該 provider 的舊列。
- connected HID 不被 disconnected `system_profiler` 覆蓋；較弱來源不改掉 canonical ID 或明確 charge state。
- 同名、不同硬體地址的非 iPhone 裝置保持兩筆；legacy single-iPhone group 有 USB reading 時 deterministic 選 USB，但不宣稱建立跨 transport identity。
- stale/expired 10% 與 100% 都不通知且不改 latch；恢復 fresh 後只發一次；fresh recovery 才 reset；disconnected 不通知。
- source sweep 與 targeted log capture 證明沒有以 public privacy 輸出名稱、ID、request ID 或百分比。

### Phase 2 — 失敗復原與誠實 onboarding

Files:

- Modify `Beacon/Mac/BeaconStatusController.swift`：觀察 diagnostics 並更新 Settings。
- Modify `Beacon/Mac/BeaconSettingsWindowController.swift`、`Beacon/Mac/BeaconSettingsView.swift`：傳入 `BatteryRefreshDiagnostics`。
- Modify `Beacon/Mac/DeviceListPresentation.swift`：新增純 presentation mapping，把 `reported/noReport/unavailable/timedOut/unauthorized/commandMissing` 轉成狀態、原因與安全下一步。
- Modify `Beacon/Mac/BeaconSettingsSupportViews.swift`：Devices 加 compact Refresh Health disclosure；Add Device 改列 Bluetooth accessories 與 iPhone USB trust/refresh 流程。
- 保留 `DeviceContextMenuAction.remove` internal case，僅把使用者文案改成「Hide from Beacon」，因現行行為只寫 hidden preference、不清資料。
- Test `BeaconTests/DeviceListPresentationTests.swift` 的 mapping、action 與各 diagnostics render state。

Acceptance checks:

- command missing、Bluetooth unauthorized、provider timeout、正常 reported 都有不同白話訊息與正確 action。
- `noReport` 不誤標為故障；畫面顯示 diagnostics 的嘗試時間，不宣稱它是即時狀態。
- Add Device 不再漏掉鍵盤、滑鼠、觸控板與現行 iPhone 路徑。
- 使用者介面與 logs 都不顯示未遮罩的 UDID/MAC/command output。

### Phase 3 — macOS 視窗禮儀與 accessibility

Files:

- Modify `Beacon/Mac/BeaconHUDController.swift`：改為 `.nonactivatingPanel` 的 `NSPanel`，以 `orderFrontRegardless` 顯示，不呼叫 `makeKeyAndOrderFront`。
- Modify `Beacon/Mac/BeaconHUDView.swift`、`Beacon/Mac/DeviceBatteryRow.swift`：所有非必要動畫尊重 Reduce Motion；複合裝置列提供一次清楚的 AX label/value，避免重複朗讀。
- Modify `Beacon/Mac/BeaconSettingsWindowController.swift`、`Beacon/Mac/BeaconSettingsView.swift`：root 改 flexible；預設與最小皆為 900×620，允許放大並以固定 autosave name 保存 frame。現有 pane 在 820pt 無法完整容納，因此本輪不做虛假的 820pt acceptance。
- Modify `Beacon/Mac/BeaconDesktopWidgetView.swift` 內 controller：監聽 window move 或每次 update 先採 live `window.frame`，移除 stale `lastKnownFrame` precedence；固定 autosave name、沿用多螢幕 clamp，並重用 hosting controller。
- Modify `Beacon/Mac/StatusMenuPanelController.swift` / `Beacon/Mac/BeaconStatusController.swift`：Escape 關閉 status panel。
- Modify `Beacon/Mac/BeaconSettingsSupportViews.swift`：selected row 加 AX selected trait 與穩定 focus order。
- Add 僅於 `#if DEBUG` 生效的 `--ui-test-show-hud` preview hook，讓 focus acceptance 不依賴真實低電量與 UserDefaults。

Manual acceptance:

- 以 DEBUG hook 在 TextEdit 輸入中觸發 HUD，前後 key window 與 first responder 不變；dismiss、auto-dismiss 均可用。
- Settings 在 900×620 與較大尺寸皆不裁切，重啟後回復尺寸與位置，⌘W 正常。
- Widget 拖曳後經資料 refresh 不跳回舊位置；跨 relaunch、compact/expanded 切換、拔除原螢幕後仍位於可見範圍。
- VoiceOver 逐列只朗讀一次完整裝置摘要；Settings selection、header buttons、AirPods components 仍可到達。

### Phase 4 — Verifier 與 UI smoke 安全網

- Modify `project.yml`：新增獨立 `BeaconMacUI` scheme，明確包含 `BeaconUITests`；production `BeaconMac` unit scheme 不混入 UI tests。
- Modify `BeaconUITests/BeaconUITests.swift`：使用僅在 `#if DEBUG` 生效的 `--ui-test-open-settings` 與 preview data；smoke 驗 app launch、Settings window、Refresh control、Escape/status-panel 路徑，不冒稱 snapshot/provider coverage。
- Modify `.github/workflows/ci.yml`：先 `xcodegen generate` 並以 clean checkout diff gate 驗 generated project；unit/UI 分開執行、保存兩份 `.xcresult`。
- 大型 provider、Settings、presentation、3,003 行 test 拆檔不支援本輪使用者 acceptance，移至獨立後續計畫，避免把機械搬動混進可靠性修正。

Acceptance:

- 不改 defaults keys、bundle ID、entitlements 或 distribution mode。
- 第一次 generate 可產生預期 tracked project diff；第二次 generate 必須 idempotent。CI clean checkout generate 後不得有 project diff。
- Unit/render/UI smoke 都由 scheme 實際執行，不得以 selected 0 tests 判為成功。

## Verification commands

```bash
xcodegen generate
cp Beacon.xcodeproj/project.pbxproj "${TMPDIR%/}/beacon-project.pbxproj"
xcodegen generate
cmp Beacon.xcodeproj/project.pbxproj "${TMPDIR%/}/beacon-project.pbxproj"
git diff --check

BEACON_RESULTS_DIR="$(mktemp -d "${TMPDIR%/}/beacon-results.XXXXXX")"
xcodebuild test \
  -project Beacon.xcodeproj \
  -scheme BeaconMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$BEACON_RESULTS_DIR/BeaconMac.xcresult" \
  CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary \
  --path "$BEACON_RESULTS_DIR/BeaconMac.xcresult"

xcodebuild test \
  -project Beacon.xcodeproj \
  -scheme BeaconMacUI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedDataUI \
  -resultBundlePath "$BEACON_RESULTS_DIR/BeaconMacUI.xcresult" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=
xcrun xcresulttool get test-results summary \
  --path "$BEACON_RESULTS_DIR/BeaconMacUI.xcresult"

BEACON_DEVELOPMENT_TEAM="" ./script/build_and_run.sh --verify
```

兩份 summary 都必須是非零 tests、零 failures。CI 以 `git status --porcelain --untracked-files=all -- Beacon.xcodeproj` 同時檢查 pbx 與 generated scheme drift。另外逐項檢查 `/tmp/batteryhub-*.png` render artifacts、provider diagnostics、TextEdit focus、VoiceOver、雙螢幕與 widget restoration。ad-hoc `--verify` 只證明 launch/path，不證明 Bluetooth TCC、development/distribution signing；未經另行指示，不執行 `--install`、DMG、簽署或公證。

## Dependencies and rollback

- External CLI verified present: Xcode 26.3、Swift 6.2.4、XcodeGen 2.45.4、`ideviceinfo` 1.4.0。
- 新增依賴、API key、token、第三方帳號：無。
- Rollback：每個 phase 僅修改 source、project/test 或本機 UserDefaults-backed window placement；可獨立回退。Phase 1 不遷移持久資料；Phase 3 的 frame autosave key 可安全忽略或刪除。
- Completion boundary：本計畫完成後仍未驗證 Developer ID、Hardened Runtime、Release DMG、Gatekeeper 或 notarization ticket；distribution readiness 必須另案處理。

## Progress and evidence

- 2026-08-14：讀取 Build macOS Apps 全部 11 個 skill descriptions；本計畫使用 build/run、SwiftUI patterns、window management、view refactor、AppKit interop、telemetry 路線。
- Phase 1：provider runner 改為 owned process group，原子化 timeout/cancel reason，provider partial outcomes、typed BLE completion、deterministic identity/merge 與 provider-aware store reconciliation 已完成；notifications 只讀 fresh/connected decorated snapshots，privacy source sweep 無 public 裝置名稱、ID/MAC、request ID 或百分比。
- Phase 2：Settings 已顯示安全的 provider refresh health、各自嘗試時間與下一步；Add Device 補齊 AirPods/Beats、鍵盤/滑鼠/觸控板與 iPhone USB Trust/Refresh；「Remove」使用者文案更正為「Hide from Beacon」。
- Phase 3：HUD 改為 nonactivating panel；Settings route、900×620 content minimum、frame autosave、widget live-frame restoration／螢幕拔除 clamp、Escape 與 AX/Reduce Motion 已完成；DEBUG Settings/status/HUD hooks 不改使用者偏好。
- Phase 4：新增獨立 `BeaconMacUI` scheme、Settings/Refresh、status Escape、HUD auto-dismiss smoke；CI 分開保存 unit/UI xcresult、驗非零 tests、檢查整個 generated project drift並上傳結果。
- Adversarial closure：battery reliability reviewer 的五個 P1（runner race、descendant pipe、BLE reason、ambiguous strong identity、Store name-dedupe）與 window reviewer 的 Settings route/content minimum、provider attemptedAt、screen notification、HUD preference findings均已修正。
- Fresh unit verification：`/tmp/beacon-final-full.BHJDCy/BeaconMac.xcresult` 為 209 passed、0 failed、0 skipped；其中 battery-focused 61/61、window/AX focused suite 均通過。
- XcodeGen：`project.pbxproj` 與 `BeaconMacUI.xcscheme` 連續兩次 generate 後 `cmp` 一致；`git diff --check` 通過。
- Render artifacts：fresh Settings、Add Device、HUD、widget、status menu PNG 均已實際檢視，未見裁切或空白 regression。
- Runtime：`BEACON_DEVELOPMENT_TEAM="" ./script/build_and_run.sh --verify` build succeeded，readback 到本 worktree `BeaconMac.app` 的 active PID；未執行 `--install`。
- UI verifier：test-only ad-hoc signed `BeaconMacUI` build-for-testing 通過；兩次 actual UI test 都在 app assertion 前被 macOS testmanagerd/CoreAuth 阻擋（一次 `Authentication canceled. System authentication is running.`，一次 `waiting for workers to materialize`，66 秒有界中止且無殘留）。CI 保持 fail-closed，不能把此項記為 pass。
- Current worktree：開始時原有未追蹤 `AGENTS.md` 保留未改；本輪 app、tests、project、CI 與計畫變更均未 commit，未執行安裝、DMG、Developer ID 或公證。
- Release evidence：目前只能證明 local tests 與 development runtime；沒有 fresh Release DMG/notarization proof，因此 release hardening 不列入本變更。

## Remaining verification limits

- 在沒有進行中的 Touch ID／系統認證、且允許 UI automation 的 macOS session 重跑 `BeaconMacUI`，取得非零 tests、零 failures 的 xcresult；目前是環境 blocker，不是已通過證據。
- CoreBluetooth TCC／powered-off／真實配件切換仍只有 typed unit mapping 與一般 runtime refresh，沒有覆蓋所有實機狀態。
- TextEdit first-responder、VoiceOver 實際朗讀與實體雙螢幕拔插仍保留為人工 QA；單元測試已覆蓋 non-key HUD、AX summary、screen notification clamp 與 frame restore。

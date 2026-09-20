# Beacon UI／UX 檢查與修正 — 2026-09-20

本次已修正截圖中的離線裝置常駐、非音訊裝置誤顯示音訊按鈕，以及相關的高度、文案與操作誠信問題，並更新本機 `/Applications/BeaconMac.app`。提交範圍限於本次 UI／UX 修正及其相關裝置清單實作；其他工作區修改保留。這份報告區分源碼、真實裝置讀回、測試資料的原生操作，以及尚未完成的驗證。

## 已修正

| 問題／根因 | 現在的行為 | 實作位置 |
| --- | --- | --- |
| `isPrimaryMenuItem` 將任何歷史 operation 與 pinned 視為主頁資格，斷線成功後仍永久留在外面 | 主頁保留已連線裝置；操作進行中暫留。離線、離線釘選、完成或失敗的離線操作都收進「其他裝置」。結果與復原仍可展開查看 | `BluetoothConnectionController.swift` |
| 未分類 Bluetooth major class 被當成音訊裝置 | 僅明確 audio/video class 或 Audio service class 才提供音訊處理；未分類本身不構成能力證據。保留非音訊裝置原本的電量與本機連線控制 | `NativeBluetoothConnectionClient.swift` |
| 已連線鍵鼠有不適用的 Connect／Use for Audio；離線列還有灰色 Disconnect | 依目前狀態只呈現適用操作；忙碌時停用，失敗保留 Check Result／Try Again／系統設定。按鈕讀屏名稱包含裝置名稱 | `BluetoothConnectionControls.swift` |
| 高度把收合區內所有歷史 operations 都算進去；單列也強制預留多列空間 | 高度只計入目前可見列與其操作；小清單收緊，長內容保留原生捲動。成功斷線後收合可回到原高度 | `BeaconStatusController.swift`、`StatusMenuView.swift` |
| 釘選設定寫「Keep visible」，與離線收合規則矛盾 | 改成「Pin to Top／釘選至最上方」，明說離線時仍收在其他裝置 | `BeaconSettingsView.swift` |
| AirPods 分段選項看起來能控制模式，實際只寫本機偏好 | 移除本機備註選項與預覽 tiles；只保留真正的 Sound Settings／Bluetooth 入口，清楚區分輸入輸出與聆聽模式設定位置。保留舊偏好資料 | `BeaconSettingsSupportViews.swift` |
| 提醒摘要使用 Global + Full，且未反映全域停用狀態；選取裝置說明截斷 | 顯示實際門檻與充滿提醒條件，停用時顯示 Alerts off；說明可完整換行 | `BeaconSettingsView.swift` |
| HUD 說明只提電量；新增裝置指引誤說一定要先收到電量 | 文案涵蓋連線進度與結果；說明已配對音訊裝置可以沒有電量回報 | `ActionHUDSettingsPane.swift`、`BeaconSettingsSupportViews.swift` |

本次觸及 10 個既有 production／DEBUG fixture／翻譯檔與 4 個既有測試檔，另更新驗收文件並新增本報告。沒有新增服務、依賴、設定開關或權限。

## 整體檢查範圍

| 表面 | 本次檢查與結果 |
| --- | --- |
| 主選單 | 真實 Keychron K3 Max、MX Master 3S B 只呈現 Disconnect；KEF EGG 與離線 AirPods 預設不出現，展開才出現 Connect。未對真實周邊執行斷線或音訊切換 |
| 裝置設定 | 選取裝置與詳情一致；iPhone 管理保留獨立入口；技術資料預設收合。AirPods 系統入口與新釘選文案已讀回 |
| 提醒 | 門檻、充滿條件、全域與裝置的關係已查源碼；英文／繁中換行已檢視。沒有發送實際系統通知 |
| 快速動作 | 實際可見開關有名稱；繁中底部的連線／斷線名稱與說明完整可讀。移轉佔位功能不在目前 UI 中 |
| 操作浮窗 | 設定頁與源碼檢查；既有 operation／queue 單元測試通過。保留同名裝置的身份資訊；不把預覽當成硬體事件驗證 |
| 儀表板／桌面小工具 | 設定預覽明示範例或最新儲存回報；兩者不混稱即時電量。來源篩選與視窗幾何由既有單元測試覆蓋；未新增多螢幕驗收宣稱 |
| 一般 | 匯出／清除／重設與支援入口分開；登入時啟動顯示 Unavailable 並提供 Refresh／系統設定，這個既有系統註冊問題尚未解決，未透過改文案假裝成功 |
| 新增裝置／iPhone | 新增裝置 sheet 實際打開，Escape 可回到設定；iPhone 前置工具與失敗路徑查源碼及既有單元測試，未重新登錄或變更信任 |
| 語言／外觀 | 英文淺色、繁中深色逐頁檢視六個設定頁；英文深色、繁中淺色抽查裝置、AirPods、提醒、快速動作與新增裝置。使用原生 App、900 × 620 內容最低尺寸與啟動參數，不寫入外觀偏好 |
| 無障礙 | CUA 的原生 AX 讀回確認裝置操作有名稱、Other devices 有數量及展開狀態、Pin to Top／Notify when charged 名稱明確、AirPods 兩個系統入口保有獨立 identifier；不宣稱完整 VoiceOver 驗收 |

選單透過專案既有 DEBUG accessibility 視窗轉接層顯示同一 `StatusMenuView`。真實裝置那一輪未啟用 preview data；連線／斷線與失敗復原使用明示的 fixture。此方式驗證內容與操作，不等同所有 production borderless panel、Spaces、背景焦點與多螢幕條件都已通過。原生畫面與 AX 讀回保存在本次對話的工具紀錄。

## 回歸與執行證據

- **Red：** 暫時恢復舊音訊分類與舊主頁資格，執行兩個新增回歸案例，得到 2 tests／5 assertion failures，確實擊中未分類音訊、離線釘選及終端 operation 常駐問題。隨後恢復修正。
- **Green：** `BeaconMac` 全套 **274 tests／0 failures**；後續加入提醒摘要測試後，相關 `DeviceListPresentationTests` 與 `BluetoothConnectionControllerTests` **169 tests／0 failures**。後者包含新增摘要測試，並非另加 169 個獨立案例。
- 最後的英文摘要文字微調與 AX 容器修正已建置、安裝並由 CUA 讀回。再次嘗試單一摘要測試時 runner 在啟動前停住，已中止，未將該次算成通過。
- **原生操作：** mixed fixture 由收合 → 展開 → 對第二台同名耳機連線 → 確認 → 斷線 → 確認 → 收合。第一台不受影響；最後只剩鍵鼠與 Other devices，歷史結果不再撐大主選單。
- **失敗復原：** audio-unverified fixture 實際顯示「Bluetooth connected; audio not confirmed」，保留 Check Result、Try Again、Sound Settings；未顯示成功，說明及按鈕可見。全離線時收合入口仍可用。
- **完整 XCTest UI：未通過／未執行案例。** macOS `Enable UI Automation` 驗證逾時，runner 無法初始化。已提出系統驗證請求；未改動系統權限或繞過它，改用既有 CUA 權限完成上述原生人工流程。
- `script/build_and_run.sh --verify` 成功；最終 `script/build_and_run.sh --install` 成功。版本 1.0 (1)，Apple Development 本機簽署，`codesign --verify --deep --strict` 通過。
- 安裝版與建置版 executable SHA-256 相同：`3f2d3646b215a838ff828ad99256af33c1b53dcee2714f3e0a3c44d3e3f3e57b`。
- `git diff --check` 與繁中 `.strings` 的 `plutil -lint` 通過。程式比較基準為 `946f67dc17183480e723e080ea699d76fb1bd276` 加上本次開始時的既有 WIP；本次未建立 PR 或執行公證發布；此處的本機驗證不代表遠端 CI 已通過。

測試摘要存於同目錄 `validation.txt`。完整重跑入口：

```sh
xcodebuild -project Beacon.xcodeproj -scheme BeaconMac   -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData   GENERATE_INFOPLIST_FILE=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic   DEVELOPMENT_TEAM=3YG3N2J423 CODE_SIGN_IDENTITY='Apple Development' test

# 完成 macOS 的 Enable UI Automation 驗證後執行：
xcodebuild -project Beacon.xcodeproj -scheme BeaconMacUI   -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData   GENERATE_INFOPLIST_FILE=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic   DEVELOPMENT_TEAM=3YG3N2J423 CODE_SIGN_IDENTITY='Apple Development' test

./script/build_and_run.sh --install
```

## 仍保留的驗證邊界

真實耳機音訊選擇／可聽見播放、耳機模式控制、實際通知送達、登入項目註冊與重新登入、完整 VoiceOver、多螢幕及正式公證／乾淨 Mac 安裝不在本次已通過項目中。與原生 UI 自動化的系統授權限制分開看待，不用單元測試或預覽畫面替代。對已指出的 UI 缺陷，狀態是 **resolved with caveats**；登入項目與硬體接受測試仍需獨立處理。

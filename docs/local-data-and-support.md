# Local data, updates and support / 本機資料、更新與支援

## 本機資料與管理

Beacon 以本機裝置識別碼區分裝置，用於配對電量回報、個別提醒與顯示偏好；不能只靠可能重複或變動的名稱。iPhone 登錄另外保存 UDID、顯示名稱與登錄時間，用來決定 Beacon 可向哪些已信任裝置讀取電量。這不是帳號或雲端同步服務。

電量歷史保存裝置識別碼、時間、電量、充電狀態與來源。在記錄新樣本時，保留最近七天、每台最多 96 筆；App 未執行時不會在背景定時刪除舊資料。一般設定的「匯出歷史記錄」會開啟原生存檔視窗；取消不會建立檔案。「清除歷史記錄」需確認，不會改動登入啟動。CSV 包含裝置識別碼與時間，分享前請先檢查、遮蔽不需公開的內容。

「重設 App 偏好設定」不是單純刷新：它清除目前 `Beacon.` 前綴的設定，但保留電量歷史，不變更系統的登入啟動註冊。這包含 Beacon 的裝置顯示、提醒、捷徑與 iPhone 登錄資料；舊版本的相容資料可能另外保留。不需要藉由重設來檢查登入狀態。iPhone 的「忘記」只移除 Beacon 的登錄，不等於撤銷 macOS／iPhone 的系統配對與信任。

## 登入啟動復原

一般設定顯示 macOS `SMAppService.mainApp.status` 的實際狀態。「需要核准」不等於已啟動；「無法使用」也不證明是憑證問題。請開啟「登入項目設定」確認允許狀態，再回到 Beacon 或按「重新整理」。操作失敗時保留錯誤，返回 App 本身不會被當成修復成功。

需要回報時，可展開登入啟動的「回報」區查看執行中的 App 版本、Bundle ID 與所在路徑，並記錄 macOS 版本及重現步驟。路徑可能包含使用者名稱，貼到公開 issue 前請遮蔽。請勿上傳憑證私鑰、密碼、完整裝置診斷或未遮蔽的 UDID。

## 更新與支援

一般設定的「直接下載版」入口開啟 [GitHub Releases](https://github.com/isaac-ys-lin/beacon/releases)，「回報」入口開啟 [問題回報](https://github.com/isaac-ys-lin/beacon/issues/new)。版本頁存在不代表已有下載檔，也不保證個別產物已完成 Developer ID 簽署、公證或乾淨 Mac 驗收。沒有新版時，請保留目前版本；不要以開發建置冒充正式更新。Beacon 不新增背景更新服務。

## English

Beacon uses local device identifiers to associate reports and per-device display, alert and shortcut preferences. iPhone enrollment stores the UDID, display name and enrollment time. Names alone are not reliable device identities. There is no Beacon account or cloud synchronization.

Battery history stores device ID, timestamp, percentage, charge state and source. On recording new samples, history is pruned to seven days and at most 96 samples per device; this is not a background deletion schedule while the app is closed. General settings can export a CSV through the native save panel or clear history after confirmation. Canceling export creates no file. CSVs contain identifiers and timestamps: review and redact before sharing.

Reset App Preferences is not a refresh. It removes current `Beacon.` preferences except battery history, including device preferences and Beacon's iPhone enrollment; legacy compatibility data may remain. It does not change the system login-item registration. Forgetting an enrolled iPhone removes Beacon's enrollment only, not the operating system's pairing or trust.

Launch at Login reflects the system's observed registration status. A request being accepted is not proof that registration is enabled. Use Open Login Items Settings, return to Beacon and recheck; Unavailable by itself does not establish a signing root cause. The expandable Report section identifies the running bundle/version/path. Redact user names and device identifiers before posting an issue. Never share signing keys or passwords.

The Releases and Report links open the project's release list and issue form. A release page is not evidence of a signed, notarized, independently installable download. Updates remain manual; no update service or background downloader is added.

### Implementation references

- `Beacon/Shared/BatteryHistoryStore.swift` — retained samples, CSV and clear.
- `Beacon/Mac/TrustedIPhoneRegistry.swift` — local enrollment and compatibility keys.
- `Beacon/Mac/GeneralSettingsSupport.swift` — registration state, reset and native export.
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) — authoritative registration status and Login Items settings entrypoint.

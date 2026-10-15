# TouchMiddle 0.4.0-beta.1 發布驗證

日期：2026-10-15（Asia/Taipei）。App：0.4.0／build 6；tag：`v0.4.0-beta.1`。Apple M5、arm64、macOS 27.0.1。

## 自動測試與候選包

- 150 項 Swift 測試（核心 128、App 22）及 9 項 Python 版本工具測試通過，0 失敗；來源與 bundle 版本一致。
- 固定本機簽章版與公開 ad-hoc 版的 release 建置均通過。公開 ZIP 解壓後確認 App 為 0.4.0／build 6、測試版識別 `beta.1`，執行檔為 arm64，嚴格簽章驗證通過。
- ZIP 僅含 App、LICENSE、INSTALL.md、SIGNING.md、OPERATION.txt 與 RELEASE-NOTES.md；文件與來源逐位元相同，App 內 LICENSE 也匹配。未包含規則、診斷、原始 trace 或憑證私鑰。
- ZIP 540,719 bytes；SHA-256：`d2cc03d6dc347598fda9c97c9de1d10e1bd03239a286f0f86c4ef460a706b582`。
- 封裝白名單、路徑／symlink 檢查、憑證字串及不應出現的品牌資訊掃描通過。此檢查不代表 Apple 公證或安全保證。
- 原始測試、建置與結構化檢查結果保留於 Git 忽略的 `outputs/release-0.4.0-beta.1-validation/`；公開候選包位於 `outputs/TouchMiddle-0.4.0-beta.1-macos-arm64/`。

## 本機安裝

- 已正常結束舊 App，再將固定本機簽章版安裝至 `/Users/chunghan/Applications/TouchMiddle.app` 並從該路徑啟動；新程序 PID 8807。
- `verify-signing-continuity.py --require-code-change` 通過：新舊程式雜湊不同，且彼此符合相同 designated requirement；安裝後的嚴格簽章驗證通過。
- 已安裝執行檔與測試產物 SHA-256 一致：`9147ee0dc3c51cd7e662ca7953aa942ee75fc576d8a2a0f3c2139748c4738a33`。
- 安裝前後 `rules.json` SHA-256 均為 `bfdbcf34dff75c2ee8335dee331c977b9a183e5553e304cb69d80997cb9db954`，3 條既有規則成功載入。舊 App、規則與偏好設定備份於 Git 忽略的 `outputs/local-install-0.4.0-beta.1-20261015-150807/`。
- 新 session `58F105A3-ED51-41A2-B136-0012C7102AB7` 確認 `accessibility=true`、`postEventAccess=true`、`listenEventAccess=true`、`enabled=true`、`sourceRunning=1`。這是啟動與來源狀態證據，不代表已完成真人手勢驗收。
- 已安裝 App 啟動後成功自動查詢 GitHub，偏好設定保存成功時間與當時最新公開 tag `v0.3.0-beta.1`，沒有查詢錯誤。
- UI 工具初次讀到新版視窗與 3 條規則；切換設定頁時回報 `Sky Computer Use native pipe closed before response`。因此本輪未完成直接點擊手動檢查按鈕的實機驗收；升版前的隔離畫面與按鈕測試見 UPDATE-CHECKING.md。

## 發布檢查

候選包與附件已完成本機核對。公開 API、tag commit 及匿名下載雜湊在發布後另行回讀，不能由候選包驗證推定公開下載成功。

## 未驗證範圍

新增手勢及實體組合鍵的真人逐項操作、目標 App 完成動作、實際等待 24 小時的更新排程、sleep/wake、重新登入、長時間使用，以及其他 Mac／Intel／外接 Magic Trackpad 的安裝與權限流程。自動測試不替代上述驗收。

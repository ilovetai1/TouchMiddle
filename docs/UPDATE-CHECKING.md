# GitHub 更新檢查

日期：2026-10-15（Asia/Taipei）。此功能包含於 `0.4.0-beta.1`；舊的 `0.3.0-beta.1` 安裝包不含此功能。沒有新增外部 Swift 套件或其他服務，也不需要 GitHub 登入或 token。

## 操作與排程

- 「狀態與設定 → 軟體更新」及選單列「檢查更新…」可手動檢查。
- App 啟動後檢查是否已滿 24 小時；持續執行時每分鐘確認一次是否到期。App 關閉或 Mac 睡眠時不執行，恢復執行後再檢查。這是兩次查詢至少間隔 24 小時，不是固定午夜排程。
- 所有查詢嘗試（含手動及失敗）均保存時間。重新開啟不重複自動查詢；一般失敗可手動重試。GitHub 限流時，手動檢查也須等待伺服器指定時間。
- 新版會顯示更新視窗，提供版本、更新內容及「開啟下載頁」。同一版本只自動提示一次，手動檢查仍可再次開啟。最近成功的結果會保留，查詢失敗同時顯示錯誤與成功時間，不將快取當成本次成功。
- 下載頁限定此專案的 GitHub Release；由預設瀏覽器開啟，不在 App 內下載或安裝。更新後的輔助使用授權仍須由使用者處理。

## 版本與資料

使用 `GET https://api.github.com/repos/ilovetai1/TouchMiddle/releases?per_page=100&page=N`，包含正式版與測試版、排除草稿。不依列表發布時間判斷新版，而以 SemVer 比較 `vX.Y.Z[-prerelease]`；例如 `beta.10 > beta.2`，同版號正式版高於測試版。無法辨識的 tag 不參與比較；完全沒有可比版本時顯示錯誤。一次最多讀取 10 頁，未能讀完整清單時顯示錯誤，不宣稱已是最新版本。

本機版本來自 App plist 的 `CFBundleShortVersionString`，測試版後綴來自 `TMPrereleaseIdentifier`。例如來源 `0.4.0` 與 `beta.1` 合為 `0.4.0-beta.1`。正式版須移除後綴 key，對外發布時 tag 必須匹配此完整版本；build 仍獨立遞增。詳見 [VERSIONING.md](VERSIONING.md)。

只向 GitHub 發送版本查詢，不傳送使用者規則、診斷或觸控資料。查詢結果及時間保存在本機 App 偏好設定。更新內容以文字顯示，不執行 HTML 或載入遠端圖片。

API 依據：[GitHub Releases API](https://docs.github.com/en/rest/releases/releases)、[GitHub API 流量限制](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)、[限流處理](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)。未登入的 API 額度依對外 IP 計算，同辦公室使用者可能共用。

## 升版前的開發驗證

- Swift 自動測試：150 項通過（核心 128、App 22），含 21 項新增更新相關測試；涵蓋版本排序、草稿、分頁、每日邊界、重啟、並行查詢、手動檢查、一次提示、錯誤與限流、下載 URL。
- Python 版本工具：9 項通過；來源版本一致性檢查通過。
- `build-app.sh` 的 release 建置、來源與 bundle 版本檢查、`codesign --verify --strict` 通過；產物為 `outputs/TouchMiddle-update-check-20261015.app`，使用既有本機固定簽章，沒有替換已安裝 App。這不代表完成 Apple 公證。
- 使用正式 `GitHubReleaseClient` 實際查詢成功，讀到當時公開的 `v0.3.0-beta.1`、`v0.2.2-beta.1` 與 `v0.2.1-beta.1`。升版前來源的 `0.3.0-beta.1` 顯示已是最新版本。
- 以相同 GitHub 查詢結果及模擬的舊版本機資訊 `0.2.2-beta.1` 驗證：顯示新版 `0.3.0-beta.1`、完整更新內容（3,365 UTF-8 bytes），下載動作回傳正確 Release 頁 URL。瀏覽器動作使用可觀察的測試替身，未實際開啟瀏覽器。
- 使用實際 `UpdateView` 的 NSHostingView 擷取畫面，已檢視版本、長篇更新內容的捲動區與下載按鈕排版。截圖位於 `outputs/update-check-validation/update-preview.png`；其中舊版本機資訊為模擬資料。未啟動完整 TouchMiddle 或變更觸控／權限狀態。
- 自動測試 log、建置 log 與實際查詢 probe 位於 Git 忽略的 `outputs/update-check-validation/`。
- 未驗證：實際等待 24 小時及睡眠／喚醒後的排程、同仁 Mac 的安裝與權限流程。自動測試的可控時間不代表完成全天實機驗收。

上述為升版前的開發驗證；本輪測試版的建置、安裝與發布驗證見 [BETA-VERIFICATION-0.4.0-beta.1.md](BETA-VERIFICATION-0.4.0-beta.1.md)。

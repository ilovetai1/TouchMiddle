# TouchMiddle 0.4.0-beta.1

GitHub Pre-release；MIT 授權，作者 ilovetai1。App 版本為 0.4.0（build 6）。

## 更新內容

- 新增 GitHub 更新檢查，支援正式版與測試版。App 執行期間每 24 小時自動檢查一次；重開保留檢查時間，手動檢查可立即查詢。
- 選單列「檢查更新…」及「狀態與設定 → 軟體更新」顯示檢查狀態。有新版時顯示更新內容，按「開啟下載頁」即可到 GitHub 下載，再手動替換 App。
- 同一新版只自動提示一次；保留上次成功結果，連線失敗、無效資料及 GitHub 限流會明確顯示，不將失敗當成已是最新版。不需要 GitHub 登入。
- 首次於公開包提供兩指固定後的左／右點擊，以及一指固定左／右點擊、兩指固定第三指上／下滑、四指輕點、三指長按、四角兩指輕點及兩指固定左／右雙擊，合計 17 種手勢。新增手勢須自行建立規則，真人觸控板逐項驗收尚未完成。
- 規則可指定需按住的 ⌘／⌥／⌃／⇧。先按住指定組合再開始手勢，途中換鍵會取消；未勾選代表這四種鍵都未按住。

## 設定相容性

新版可讀舊的 version 1 規則；儲存規則時使用 version 2。**舊 App 無法讀取 version 2。** 更新前請備份規則與舊 App；需要降版時，一併還原舊規則備份。更新不需要刪除規則。

## 下載與安裝

下載 `TouchMiddle-0.4.0-beta.1-macos-arm64.zip`，適用 Apple Silicon Mac。App 宣告最低 macOS 14；實機環境僅涵蓋 Apple M5 內建觸控板、macOS 27.0.1，其他組合尚未完整驗證。不需要 Xcode。「Source code」ZIP 是原始碼。

1. 結束舊版 App，備份 `~/Library/Application Support/TouchMiddle/rules.json` 與舊 App。
2. 解壓縮，將 `TouchMiddle.app` 放到固定的 `/Applications` 或 `~/Applications` 位置，替換舊版。
3. 公開包使用 ad-hoc 簽章，沒有 Apple Developer ID 或公證。若提示無法驗證開發者，確認來源可信後，到「系統設定 → 隱私權與安全性」選「仍要打開」。若提示惡意軟體或檔案受損，停止安裝。
4. 檢查「輔助使用」權限。若權限失效，結束 App，移除舊項目並加入固定安裝位置的新版，再重新開啟。
5. 檢查規則，碰一下觸控板後完全放開完成校準，實際測試自己的動作。

從舊版取得更新檢查功能，須先手動安裝本版一次。之後有新版可由 App 得知，下載及安裝仍由使用者操作。更新檢查不會上傳規則或診斷。完整安裝與簽章說明附於下載包；不需要關閉 Gatekeeper 或安裝作者憑證。

## 驗證範圍與限制

150 項 Swift 測試與 9 項版本工具測試通過。封裝、本機安裝與公開下載驗證見 [0.4.0-beta.1 驗證紀錄](https://github.com/ilovetai1/TouchMiddle/blob/main/docs/BETA-VERIFICATION-0.4.0-beta.1.md)。本機固定簽章建置的驗證，不代表公開 ad-hoc 包在其他 Mac 的權限流程已通過。

新增手勢及實體組合鍵的真人逐項操作、目標 App 動作、實際等待 24 小時的更新排程、sleep/wake、重新登入、長時間使用、Intel 及外接 Magic Trackpad 尚未完整驗證。使用 MultitouchSupport 私有 framework，macOS 更新後需重新驗證。可能漏判、誤觸或與原生手勢同時觸發；事件送達不保證目標 App 完成動作。

ZIP 附 App、LICENSE、INSTALL.md、SIGNING.md、OPERATION.txt 與本更新說明；Release 另附 `SHA256SUMS.txt`。SHA-256 用於檢查下載完整性，不代表 Apple 公證或安全保證。

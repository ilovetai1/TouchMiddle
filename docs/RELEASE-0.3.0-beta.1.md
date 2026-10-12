# TouchMiddle 0.3.0-beta.1

GitHub Pre-release；MIT 授權，作者 ilovetai1。App 版本為 0.3.0（build 5）。

## 更新內容

- 新增「狀態與設定 → 選單列圖示 → 在選單列顯示 TouchMiddle 圖示」開關。預設顯示，重啟後會記住選擇。
- 隱藏圖示後，App 保持執行，手勢啟用狀態及觸控來源不受此開關影響。
- 圖示隱藏且設定視窗已關閉時，再次開啟 TouchMiddle.app 可回到設定並恢復圖示。
- 選單列改由 AppKit 管理，保留啟用／暫停手勢、開啟設定及結束 App 的操作。黑白 S1 圖示與既有手勢規則保留。

## 下載與安裝

下載 `TouchMiddle-0.3.0-beta.1-macos-arm64.zip`。此包僅適用 Apple Silicon（arm64）；App 宣告最低 macOS 14，其他裝置與系統版本尚未完整驗證。

ZIP 包含 App、LICENSE、INSTALL.md、SIGNING.md、OPERATION.txt 與 RELEASE-NOTES.md。另附 `SHA256SUMS.txt`、安裝及簽章說明。SHA-256 用於核對下載完整性，不代表 Apple 公證或安全保證。

1. 更新前先結束舊版 App，並備份規則及舊 App。
2. 解壓縮，將 App 放入 `/Applications` 或 `~/Applications`。
3. 此包使用 ad-hoc 簽章，沒有 Apple Developer ID 或公證。若提示無法驗證開發者，確認來源可信後，在「系統設定 → 隱私權與安全性」選擇「仍要打開」。若提示惡意軟體或檔案受損，停止安裝。
4. 到「隱私權與安全性 → 輔助使用」允許 TouchMiddle。若舊權限失效，先結束 App、移除舊項目、加入目前安裝的新版 App，再重新開啟。
5. 確認規則與手勢啟用狀態。先碰一下觸控板，再完全放開完成校準。

完整步驟見安裝包的 INSTALL.md 與 SIGNING.md；不需要關閉 Gatekeeper 或安裝作者憑證。

## 驗證範圍與限制

73 項 Swift 與 8 項版本工具測試通過。公開候選 ZIP 的版本、arm64 架構、ad-hoc 簽章、圖示、文件及 SHA-256 檢查結果見 `docs/BETA-VERIFICATION-0.3.0-beta.1.md`。

選單列設定已在作者本機的固定簽章建置驗證：隱藏後 App 持續執行，手勢仍為啟用且觸控來源運行；重啟記住隱藏選擇，關閉視窗後重開及恢復圖示均通過。詳見 `docs/MENUBAR-VERIFICATION.md`。這些實機結果不代表其他 Mac 的 ad-hoc 公開包已完成權限或手勢驗收。

本輪未重做真人手勢事件輸出、重新登入或其他 Mac 安裝驗收。Intel、外接 Magic Trackpad、其他 macOS 版本、真實 sleep/wake、長時間使用與任意掌心接觸尚未驗證。

使用 MultitouchSupport 私有 framework，macOS 更新後需重新驗證。手勢可能漏判、誤觸或與原生手勢同時觸發；事件送達不保證目標 App 完成動作。沒有自動更新服務。

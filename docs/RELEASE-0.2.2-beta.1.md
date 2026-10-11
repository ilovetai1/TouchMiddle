# TouchMiddle 0.2.2-beta.1

GitHub Pre-release；MIT 授權，作者 ilovetai1。App 版本為 0.2.2（build 4）。

## 更新內容

- App、選單列與設定頁改用黑白 S1 圖示；建置工具產生並封裝 AppIcon.icns。
- 每次啟動時，若輔助使用及事件輸出權限、設定與觸控來源正常，手勢預設啟用；適用於手動開啟與登入自動啟動。先碰一下觸控板，再完全放開完成校準。啟動時尚未取得權限者，授權後需手動啟用手勢。
- 保留設定錯誤、權限失效與觸控來源失敗時的暫停機制；已儲存規則會保留。
- 修正版本工具的新紀錄插入位置，完整保留 beta 歷史；修正版本漂移測試的檢查目標。
- README 補上 REA／Ghidra 研究與開發過程，以及分析和驗收限制。

## 下載與安裝

下載 `TouchMiddle-0.2.2-beta.1-macos-arm64.zip`。此包僅適用 Apple Silicon（arm64）；App 宣告最低 macOS 14，其他裝置與版本尚未完整驗證。

ZIP 包含 App、MIT 授權、安裝步驟、簽章說明、操作說明與更新說明。另附 `SHA256SUMS.txt`、`INSTALL.md` 與 `SIGNING.md`。SHA-256 用於核對下載完整性，不代表 Apple 公證或安全保證。

1. 解壓縮，將 App 放入 `/Applications` 或 `~/Applications`。
2. 此包使用 ad-hoc 簽章，沒有 Apple Developer ID 或公證。若提示無法驗證開發者，確認來源可信後，在「系統設定 → 隱私權與安全性」選擇「仍要打開」。若提示惡意軟體或檔案受損，停止安裝。
3. 到「隱私權與安全性 → 輔助使用」允許 TouchMiddle。更新後若舊權限失效，先結束 App、移除舊項目、加入目前安裝的新版 App，再重新開啟。
4. 檢查規則並完成觸控校準。若尚未自動啟用，手動開啟「啟用手勢」。

更新前請結束舊 App，並備份規則。完整步驟見安裝包的 `INSTALL.md` 與 `SIGNING.md`；不需要關閉 Gatekeeper 或安裝作者憑證。

## 驗證範圍與限制

本版測試與候選包檢查結果見 `docs/BETA-VERIFICATION-0.2.2-beta.1.md`。自動測試與封裝檢查不替代真人手勢或其他 Mac 安裝驗收。

使用 MultitouchSupport 私有 framework；macOS 更新後需重新驗證。可能漏判、誤觸或與原生手勢同時觸發。事件送達不保證目標 App 完成動作。

Intel、外接 Magic Trackpad、其他 macOS 版本、其他 Mac 的 Gatekeeper／權限流程、重新登入、真實 sleep/wake、長時間使用與任意掌心接觸尚未驗證。沒有自動更新服務。

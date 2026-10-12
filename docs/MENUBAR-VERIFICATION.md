# 選單列圖示設定驗證

日期：2026-10-12（Asia/Taipei）。新增功能本機版本為 0.3.0／build 5；此紀錄建立時尚未發布到 GitHub Releases。

## 實機結果

- 開關初始顯示，App 的選單列項目存在。透過設定頁關閉開關後，項目消失；同一個 App process 持續執行。診斷狀態仍為 `enabled=true`、`sourceRunning=1`，輔助使用及事件輸出權限均為 true。
- 在圖示隱藏時關閉設定視窗，視窗數為 0；再次開啟相同 App，原 process 開出設定視窗，圖示保持隱藏。
- 結束 App 後重開，新 process 的圖示開關仍為關閉，選單列項目仍不存在；手勢啟用及觸控來源運行狀態正常。
- 在重開的設定視窗開啟圖示開關，選單列項目恢復。測試結束保留圖示顯示。
- 測試前後規則檔 SHA-256 一致。原有登入項目設定未操作。

73 項 Swift 與 8 項版本工具測試通過。候選 App 使用既有固定本機簽章身分，與原安裝版的 designated requirement 相同；建置、版本與嚴格簽章檢查通過。

UI 操作使用已獲使用者授權的 AppleScript／macOS Accessibility。原生 UI 工具重連仍回報 `native pipe closed`。原始觀察及狀態快照保留於本機 `work/menubar-validation-20261012-qs5rk2vh/`，不納入 Git。

## 本機部署

已部署至 `~/Applications/TouchMiddle.app`（0.3.0／build 5）。安裝後執行檔 SHA-256 與已驗證候選一致；designated requirement 與原安裝版相同，嚴格簽章及版本檢查通過。

已確認從原安裝位置啟動，圖示顯示、設定視窗存在，`enabled=true`、`sourceRunning=1`，輔助使用及事件輸出權限正常；2 條既有規則保留。舊 App 備份位於 `work/menubar-validation-20261012-qs5rk2vh/TouchMiddle-before.app`。部署狀態記錄位於同目錄的 `installed.json` 與 `installed-live-status.json`。

## 限制

本輪確認隱藏圖示不會停用手勢或停止觸控來源；沒有重做真人手勢事件輸出、重新登入或其他 Mac 驗收。此結果不代表所有第三方 App 均能執行快捷鍵。

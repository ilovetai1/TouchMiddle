# Repository Guidelines

## 專案結構與模組

TouchMiddle 是 macOS 觸控板手勢與快捷鍵選單列 App。SwiftPM 套件位於 `touchmiddle/`，需要 macOS、Xcode／Swift 6 與 Python 3；套件宣告最低 macOS 14，沒有外部 Swift 套件依賴。

- `Sources/TouchMiddle/`：SwiftUI 介面、規則儲存、登入項目與事件輸出。
- `Sources/TouchMiddleCore/`：手勢模型、辨識器與規則解析；將可獨立測試的邏輯放在此處。
- `Sources/CTouchBridge/`：MultitouchSupport 私有 framework 的 C bridge。
- `Tests/`：核心與 App 的 XCTest；`Tools/`：建置、圖示產生與獨立事件接收端。
- 根目錄 `scripts/`：版本工具及其 Python 測試；`docs/`：安裝、簽章、版本與驗收文件。
- `outputs/`、`work/`：Git 忽略的本機產物、研究材料與診斷資料。

## 建置、測試與本機開發

以下命令從儲存庫根目錄執行：

```bash
# 執行 Swift 測試
xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-tests
# 執行版本工具測試，使用臨時儲存庫
python3 -m unittest discover -s scripts/tests
# 核對來源版本與當期文件
./scripts/check_version_consistency.sh
# 建立 App；目的地必須尚未存在
bash touchmiddle/Tools/build-app.sh --output /tmp/TouchMiddle-dev.app
```

建置後手動開啟 App。觸控輸出需輔助使用權限；每次啟動預設暫停手勢。建置不會授權、啟動 App 或登記登入項目。

## 程式風格與命名

沿用既有四空格縮排。Swift 型別與檔名使用 `UpperCamelCase`，函式、屬性及列舉 case 使用 `lowerCamelCase`；C 匯出介面沿用 `TM` 前綴。維持 Swift concurrency 的隔離與 `Sendable` 契約。沒有設定 formatter 或 linter，修改時保持鄰近程式碼風格。

## 測試與驗收

Swift 測試使用 `*Tests.swift` 與描述行為的 `test...` 方法；Python 使用 `test_*.py` 與 `test_...`。沒有設定覆蓋率門檻。手勢改動應涵蓋時間邊界、取消、校準及 App／PID 切換；規則改動應涵蓋優先順序與無效設定。

涉及 bridge、事件輸出、簽章或登入項目時，另做對應實機驗收，並在 `docs/` 記錄環境、觀察結果與未驗證項目。事件送達不等於目標 App 已完成動作；單元測試不替代實機驗收。

## Commit 與 Pull Request

現有 commit 使用英文祈使句，例如 `Add macOS launch at login setting`，沒有固定 Conventional Commits 前綴。每次 commit 聚焦單一改動。PR 應說明問題、行為變更、驗證結果與限制；有相關 issue 時附連結，介面變更附截圖。

## 設定、版本與操作界線

版本以 `touchmiddle/Tools/Info.plist` 為唯一來源；升版前讀取 `docs/VERSIONING.md`，簽章改動前讀取 `docs/SIGNING.md`。無效設定應明確報錯，保留既有正常預設值。secret、私鑰與原始 trace 留在本機。保留使用者既有修改；commit、push／tag、發布及替換已安裝 App 須有明確授權。

# TouchMiddle

macOS 原生觸控板手勢與快捷鍵工具。支援兩指／三指雙擊、快捷鍵錄製，以及全域與 App 專屬規則；保留三指輕點中鍵功能。

- `touchmiddle/`：Swift 原始碼、測試、建置工具與詳細操作說明。
- `docs/`：可納入版本控制的驗收摘要。
- `outputs/`：本機安裝包、完整驗收記錄與 BTT 逆向分析交付，不納入 Git。
- `work/`：本機原始證據、獨立接收端記錄、下載檔、分析工具與工作檔，不納入 Git。

目前已安裝版本為 0.2.0，位於 `/Users/chunghan/Applications/TouchMiddle.app`。

[操作與建置說明](touchmiddle/README.txt) · [0.2.0 驗收摘要](docs/VERIFICATION.md)

## 建置與測試

需要 macOS、Xcode/Swift 6；不依賴外部 Swift 套件。從倉庫根目錄執行：

```bash
xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-tests
bash touchmiddle/Tools/build-app.sh --output /tmp/TouchMiddle.app
```

App 建置目的地必須尚未存在。建置工具只產生並驗證本機臨時簽章的 App，不會替換已安裝版本或變更系統權限。使用 MultitouchSupport 私有 framework，目前只驗證內建觸控板；最低 macOS 14 是套件宣告，並非全版本驗收。

完整原始驗收記錄位於本機 `outputs/touchmiddle-0.2.0-verification.json`；搬移記錄位於 `outputs/project-relocation.json`。這些檔案與原始觸控資料留在本機。

本專案於 2026-10-11 搬至 `/Users/chunghan/AI/TouchMiddle`。舊工作區 `/Users/chunghan/Documents/Codex/2026-10-11/new-chat` 保留為指向此處的相容連結；歷史證據中的絕對路徑因此仍可解析。專案檔案只存放在新位置。

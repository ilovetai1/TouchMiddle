# TouchMiddle

[English](README.md)

macOS 原生選單列 App，把觸控板手勢轉成鍵盤快捷鍵或中鍵。你自己選手勢、動作，以及規則要套用到所有 App 或單一 App。

## 能做什麼

- **17 種觸控板手勢**，見下表。
- **兩種動作**：自行錄製的快捷鍵（可含 ⌘ ⌥ ⌃ ⇧），或在游標位置按中鍵。
- **全域或指定 App 規則。** 同一手勢有已啟用的指定 App 規則時，優先於全域規則。
- **組合鍵條件。** 規則可要求操作手勢時按住 ⌘、⌥、⌃ 或 ⇧，讓同一手勢觸發不同動作。
- **更新檢查。** App 每 24 小時到 GitHub 檢查一次新版；下載與替換 App 由你自己操作。

輕點不需要壓下觸控板。每次輕點之間，手指要完全放開。

| 手勢 | 操作方式 |
|---|---|
| 三指輕點 | 三指一起輕點後放開。預設規則：中鍵。 |
| 四指輕點 | 四指一起輕點後放開。 |
| 兩指雙擊 | 兩指連續輕點兩次。 |
| 三指雙擊 | 三指連續輕點兩次。 |
| 三指長按 | 三指固定至少 500 ms，再於 2 秒內放開。 |
| 四角兩指輕點（×4） | 兩指在同一角落（寬、高各 25%）輕點：左上、右上、左下或右下。 |
| 一指固定＋左／右輕點（×2） | 一指固定 150 ms，再用另一指在它的左側或右側輕點。 |
| 兩指固定＋左／右點擊（×2） | 兩指固定 150 ms，再用第三指在兩指外側的左邊或右邊輕點。保持固定可重複點擊。 |
| 兩指固定＋左／右雙擊（×2） | 同上，第三指連續輕點兩次。 |
| 兩指固定＋第三指上滑／下滑（×2） | 兩指固定 150 ms，第三指向上或向下滑動至少觸控板高度的 6%。 |

「左」「右」以固定的手指為基準，不是觸控板的左右半邊。可移動距離、單次點按時間與雙擊間隔，可在「狀態與設定」調整。

## 安裝

1. 到 [GitHub Releases](https://github.com/ilovetai1/TouchMiddle/releases) 下載最新的 `TouchMiddle-*-macos-arm64.zip`。「Source code」壓縮檔是原始碼，不是 App。
2. 解壓縮，把 `TouchMiddle.app` 移到 `/Applications` 或 `~/Applications`。
3. 開啟 App。本 App 未經 Apple 公證，第一次開啟可能被 macOS 阻擋。確認來源可信後，到「系統設定 → 隱私權與安全性」允許。
4. 依提示授予「輔助使用」權限。
5. 新增手勢規則。接著碰一下觸控板，再完全放開，完成校準。

**權限已開，App 仍顯示未取得權限？** macOS 可能保留舊版 App 的授權。結束 TouchMiddle，在「輔助使用」清單移除舊項目，重新加入新版 App，再重新開啟。

詳細說明：[安裝、更新與移除](docs/INSTALL.md) · [簽章與權限問題](docs/SIGNING.md) · [完整操作說明](touchmiddle/README.txt)

## 系統需求與已知限制

- **僅支援 Apple Silicon。** 發布包只含 arm64。
- **只在一種環境實測。** 套件宣告支援 macOS 14 以上，但實機測試只涵蓋 Apple M5、內建觸控板與 macOS 27.0.1。外接 Magic Trackpad 與 Intel Mac 未測試。
- **使用私有 framework**（MultitouchSupport）讀取觸控資料。macOS 升級後可能失效。
- **不攔截 macOS 原生手勢。** 原生手勢與 TouchMiddle 手勢可能同時觸發。
- **可能漏判或誤觸。** 部分新增手勢尚未完成真人觸控板實測。
- **結果由目標 App 決定。** TouchMiddle 只負責送出快捷鍵，無法保證 App 會回應。
- **尚未驗證：** sleep/wake、長時間使用、各種掌心接觸，以及實際重新登入後的自動啟動。
- **隱私：** 規則與診斷資料只存在你的 Mac。唯一的網路請求是 GitHub 版本檢查。

## 背景

TouchMiddle 起於研究市場上既有觸控板工具如何處理觸控輸入。該研究以靜態分析為主，只作為設計參考。TouchMiddle 的手勢辨識與事件輸出都是本專案自行實作，不宣稱重現任何其他產品。第三方研究材料不在本倉庫中，也不在本專案授權範圍內。

## 從原始碼建置

需要 macOS、Xcode／Swift 6 與 Python 3。從倉庫根目錄執行：

```bash
xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-tests
bash touchmiddle/Tools/build-app.sh --output "$HOME/Applications/TouchMiddle.app"
```

輸出路徑必須尚未存在。簽章、打包與版本管理見 [docs/BUILDING.md](docs/BUILDING.md)；版本紀錄見 [CHANGELOG](CHANGELOG.md)。

## 授權

[MIT](LICENSE) © [ilovetai1](https://github.com/ilovetai1)。軟體按現況提供，不附保固。

# 版本管理規範

TouchMiddle 使用三段式版本、單一版本來源與明確的發布授權原則。此規範自建立後的版本操作適用；不回溯重編既有版本。目前版本與 build 以來源 plist 及 README 的當期版本欄位為準。

## 升版原則

版本格式為 `major.minor.patch`，三段均為非負整數，不使用前導零。

| 類型 | 適用改動 | 算法 | 從 0.2.1 升版範例 |
| --- | --- | --- | --- |
| major | 破壞既有設定格式、公開介面或既有使用方式的相容性 | major 加一，minor 與 patch 歸零 | 1.0.0 |
| minor | 新增功能，且維持既有相容性 | minor 加一，patch 歸零 | 0.3.0 |
| patch | 相容的錯誤修正 | patch 加一 | 0.2.2 |

同一版本包含多種改動時，採最高層級。`0.x` 階段仍使用上表規則。純文件、測試或開發工具調整不必自動升 App 版本；需要重新發布 App 時，依實際產品改動決定層級。每次 commit 不等於一次升版。

## 單一真相來源

- App 版本唯一來源（SSOT）是 `touchmiddle/Tools/Info.plist` 的 `CFBundleShortVersionString`。Swift 專案沿用既有 plist，不為了複製 Python 專案結構新增 `pyproject.toml`。
- `CFBundleVersion` 是 macOS build 編號，使用遞增正整數；每次對外發布新建置時加一，不隨 major 或 minor 歸零。它不參與三段式版本算術。
- `touchmiddle/Tools/build-app.sh` 直接複製來源 plist 到 App bundle。建置產物版本必須與來源一致。
- README、操作說明、未來的版本顯示與發布紀錄都是派生資訊，不得各自決定版號。升版時同步當期文件；歷史驗收紀錄保留原版號。
- 設定資料的 `RuleConfiguration.version` 與 Swift tools version 各自有不同用途，不隨 App 版號調整。

## 版本與發布操作

1. 先依產品改動決定升版層級，再同步 App 版本、build 編號與當期文件。發布紀錄記載日期、改動摘要、驗證結果及未驗證事項。
2. 建置或發布前，核對來源 plist、當期文件與新 App bundle 的版本。若不一致，必須中止並回報，不以預設版本掩蓋錯誤。
3. 經授權建立版本 commit 時，只包含當次版本相關檔案，不帶入其他已暫存改動。
4. 經授權發布時，使用 annotated tag `vX.Y.Z`，並只推送當次精確 tag，不使用批次 `--tags`。
5. 本機改檔或升版不等於已發布、已安裝或已通過實機驗收。commit、push／tag 與替換已安裝 App 依使用者明示的 target、版本及動作授權執行。

使用 `./scripts/bump_version.sh <major|minor|patch> "摘要"` 同步來源 plist、README 當期版本欄位、操作說明首行及 CHANGELOG 最新紀錄，build 同時加一。`current` 只讀來源；`--dry-run` 先驗證並預覽，不改檔。升版前若來源或派生資訊不一致，工具會以非零狀態中止，不自動修補漂移。

`./scripts/check_version_consistency.sh` 核對上述檔案；加上 `--app /絕對路徑/TouchMiddle.app` 會核對 bundle 的 App 版號及 build。建置工具在編譯前及簽章前執行此檢查。不安裝 Git hook，不宣稱已有 pre-push 硬閘。

工具不自動 commit、tag、push 或安裝。每個檔案以暫存檔原子替換，但多檔更新不是單一交易；若遇到磁碟或權限錯誤，命令會失敗，須檢查檔案狀態再重試。CHANGELOG 的驗證與未驗證欄位須在發布前填寫。歷史 beta 發布說明及固定版本打包腳本不自動改寫，下一版本須另行準備發布素材。

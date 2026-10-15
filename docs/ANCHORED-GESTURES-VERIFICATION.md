# 兩指固定左右側點擊驗證紀錄

日期：2026-10-12（Asia/Taipei）。範圍：目前原始碼與本機開發建置，尚未公開發布。

## 操作與判定

- 新增「兩指固定左側點擊」與「兩指固定右側點擊」。規則可指定全域或個別 App，動作沿用中鍵與鍵盤快捷鍵。
- 兩指可一起或逐一放下。兩指同時保持接觸且固定至少 150 ms 後，第三指才能開始輕點。固定手指沒有最長等待時間；仍須持續收到有效影格。
- 左右相對於固定兩指判定。第三指須位於兩指外側，水平間隔須超過「可移動距離」設定；預設為觸控板寬度的 2.5%。兩指之間及邊界附近不觸發。
- 第三指放開且原本兩指仍接觸時才觸發。兩指與第三指都使用既有位移限制。第三指使用單次輕點時間限制，預設 15–250 ms；不把固定兩指的等待時間算入第三指輕點。
- 固定兩指時可重複點擊。動作之間沿用 250 ms 冷卻；冷卻內開始的第三指輕點不觸發，即使它在冷卻結束後才放開。
- 固定手勢開始後，固定指放開或替換、移動過大、掌心／取消、第四指、無效資料與影格間隔過大會取消，並等待所有手指放開。App／PID、規則、啟用狀態或設定切換沿用原本重置與校準流程。
- 短兩指點按保留既有雙擊判定；普通三指點按也可與新手勢共存。已進入固定手勢的接觸不會在最後放開時另觸發普通點按。
- 預設規則仍只有「全域三指輕點 → 中鍵」。新增手勢需自行新增規則。

## 已確認

環境：macOS 27.0.1（26A434）、arm64、Apple Swift 6.4。原始碼版本保持 0.3.0／build 5；此本機產物含尚未發布的修改，不代表公開 `0.3.0-beta.1` 安裝包有新手勢。

| 檢查 | 結果 |
| --- | --- |
| `xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-anchored-tests` | 104 項 Core、5 項 App 測試，共 109 項通過，0 failures |
| 新增固定手勢辨識測試 | 34 項通過；涵蓋左右、時間與位移邊界、逐一放指、重複點擊、冷卻、取消、裝置隔離、校準及 App／PID 切換 |
| 規則測試 | 13 項通過；涵蓋新手勢序列化、App 優先順序、重複規則與既有預設 |
| `python3 -m unittest discover -s scripts/tests` | 8 項通過 |
| `./scripts/check_version_consistency.sh` | 通過：0.3.0／build 5 |
| `git diff --check` | 通過 |
| `build-app.sh` release 建置與 bundle 檢查 | 通過；arm64 App，固定本機憑證簽章，`codesign --verify --strict` 通過 |

本機產物：`outputs/TouchMiddle-anchored-20261012.app`。建置只建立新目的地；未替換已安裝 App、修改使用者規則或登記登入項目。

本機證據：`outputs/anchored-20261012/swift-tests.log`、`outputs/anchored-20261012/build-app.log`。`outputs/` 由 Git 忽略。

## 尚未驗證

原始碼驗證階段未啟動新 App。後續本機替換與啟動結果見下方；真人觸控板及實際事件輸出驗收仍未完成。自動測試使用正規化觸控快照，不能證明私有 framework 在真實固定手勢下會持續提供影格，也不能證明目標 App 完成動作。

真人驗收需確認：

1. 在安全的接收端建立左右各一條規則，完成碰一下再完全放開的校準。分別用第三指於兩指外側輕點，核對方向、只觸發一次及實際動作。
2. 保持兩指重複點擊，核對冷卻前後、兩指間與外側邊界附近的行為。
3. 移動、放開或替換固定指，加入第四指，以及在固定期間切換 App，確認無動作輸出且須完全放開後才能重新開始。
4. 同時啟用既有兩指雙擊與三指手勢，確認普通點按仍有效，固定手勢結束不另送普通點按。
5. 檢查 macOS 原生捲動或三指手勢是否同時觸發。外接觸控板、其他硬體與其他 macOS 版本仍未驗證。

## 本機替換與啟動（2026-10-12）

使用者已明示授權用本機測試版替換已安裝 App 並開啟，由使用者測試左右手勢。

- 已將 `outputs/TouchMiddle-anchored-20261012.app` 安裝至 `/Users/chunghan/Applications/TouchMiddle.app`，新程序 PID 為 95482。安裝後執行檔 SHA-256 與測試版相同；`codesign --verify --strict` 再次通過。新舊 App 的 Bundle ID 與固定本機憑證身分一致。
- 舊 App 備份於 `work/local-redeploy-anchored-20261012-6plxec8o/TouchMiddle-before.app`；同目錄保留規則及偏好設定備份、`deployment.json`。使用者原有 `rules.json` 在替換及啟動前後 SHA-256 相同。
- 新 session 為 `/Users/chunghan/Library/Application Support/TouchMiddle/Diagnostics/session-6A5524AB-B510-4FC2-BCF8-99D37B1B5B9C.jsonl`；`sourceStarted.pid=95482`、`deviceCount=1`、`runningCount=1`。最新狀態確認 `enabled=true`、`accessibility=true`、`postEventAccess=true`、`sourceRunning=1`、`editingRule=false`。
- 已觀察新 App 的手勢規則視窗及進階手勢操作說明。狀態頁的 UI 自動化觀察未完成；以上權限與來源狀態以新程序 session 記錄查核。
- 現有兩條規則沒有左右固定手勢。使用者須在「新增規則」分別選擇左側與右側手勢、設定動作並儲存，才能測試辨識與輸出。此輪未新增或改動使用者規則，亦未記錄真人左右手勢通過。

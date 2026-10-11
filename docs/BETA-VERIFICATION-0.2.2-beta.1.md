# TouchMiddle 0.2.2-beta.1 候選包驗證

日期：2026-10-11（Asia/Taipei）。App：0.2.2／build 4。此紀錄涵蓋本機自動測試與實際候選 ZIP，不代表其他 Mac 的安裝或真人手勢驗收完成。

## 已確認

- 73 項 Swift 測試通過、0 失敗：68 項核心測試及 5 項登入項目狀態測試。
- 8 項版本工具測試通過；包含升版算法、beta 歷史保留、版本／build 漂移及錯誤時不改檔。
- Release 建置成功；來源與解壓後 bundle 均為 0.2.2／build 4，執行檔為 arm64。
- 解壓後 `codesign --verify --strict` 通過；使用 ad-hoc 簽章，沒有 Apple Developer ID 或公證。
- `CFBundleIconFile` 為 `AppIcon`，bundle 包含 AppIcon.icns；抽出圖示預覽已目視核對黑白 S1 圖形。
- ZIP 的 11 個檔案通過明確清單檢查：App bundle 必要檔案及圖示、LICENSE、INSTALL.md、SIGNING.md、OPERATION.txt、RELEASE-NOTES.md。不含規則、原始研究、憑證或診斷資料。
- ZIP 中安裝、簽章、操作及更新說明與來源逐位元一致；ZIP 與 App 內的 LICENSE 均與 repo 一致。
- ZIP 各檔案的大小寫不敏感文字掃描未發現公司識別資訊。
- SHA-256 與 `SHA256SUMS.txt` 一致：`a336f467290bb5003b2691adc71f5afba8fd4f8524a83a18c814deed12308995`。
- Shell 語法、版本一致性與 `git diff --check` 通過。

## 驗證限制

啟動自動啟用的程式已編譯，並核對權限、設定與來源錯誤時的保護條件；此次未啟動公開 ad-hoc 候選 App 作真人手勢驗收，也未替換已安裝 App。既有測試未直接覆蓋 TouchController 與 macOS 權限／觸控來源整合的完整啟動路徑。

其他 Mac 下載後的 Gatekeeper／輔助使用流程、登入自動啟動的實際登記／取消及重新登入、Intel、外接 Magic Trackpad、其他 macOS 版本、真實 sleep/wake、長時間使用與任意掌心接觸尚未驗證。事件送達不等於目標 App 完成動作。

本機原始測試 log 位於 `outputs/TouchMiddle-0.2.2-beta.1-validation/`，封裝 log 位於 `outputs/touchmiddle-0.2.2-beta.1-package.log`；候選包及結構化檢查結果位於 `outputs/TouchMiddle-0.2.2-beta.1-macos-arm64/`。這些本機資料不納入 Git。

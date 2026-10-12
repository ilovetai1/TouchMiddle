# TouchMiddle 0.3.0-beta.1 候選包驗證

日期：2026-10-12（Asia/Taipei）。App：0.3.0／build 5。

## 已確認

- 73 項 Swift 測試通過、0 失敗：68 項核心測試及 5 項登入項目狀態測試。
- 8 項版本工具測試通過。Shell 語法、版本一致性及 `git diff --check` 通過。
- Release 建置成功；來源與解壓後 bundle 均為 0.3.0／build 5，執行檔為 arm64。
- 解壓後 `codesign --verify --strict` 通過；簽章為 ad-hoc，無 Apple Developer ID 或公證。
- `CFBundleIconFile` 為 `AppIcon`，bundle 含 AppIcon.icns；抽出圖示預覽已目視核對黑白 S1 圖形。執行檔包含選單列顯示設定鍵。
- ZIP 的 11 個檔案通過明確清單檢查：App bundle 必要檔案、圖示、LICENSE、INSTALL.md、SIGNING.md、OPERATION.txt 與 RELEASE-NOTES.md。不含個人規則、憑證、原始研究或診斷資料。
- 安裝、簽章、操作與更新說明與來源逐位元一致；ZIP 與 App 內的 LICENSE 均與 repo 一致。
- repo 與 ZIP 檔案的大小寫不敏感文字掃描未發現公司識別資訊。
- SHA-256 與 `SHA256SUMS.txt` 相符：`d99c8648aff5c8bc8726934be58b1aecc21ff56c3669ff8e6332935f11df453a`。

## 實機結果與限制

圖示隱藏、重啟保留設定、關閉視窗後重開及恢復圖示，已在作者本機固定簽章建置通過驗證，詳見 [選單列圖示驗證](MENUBAR-VERIFICATION.md)。隱藏時手勢仍為啟用，觸控來源保持運行，規則檔未變動。

上述實機驗證不代表公開 ad-hoc 包在其他 Mac 的安裝與權限流程已驗收。本輪未重做真人手勢事件輸出、重新登入、其他 Mac 安裝、Intel、外接 Magic Trackpad、其他 macOS 版本、真實 sleep/wake、長時間使用或任意掌心接觸。

原始測試 log 位於本機 `outputs/TouchMiddle-0.3.0-beta.1-validation/`，封裝 log 位於 `outputs/touchmiddle-0.3.0-beta.1-package.log`；候選包與結構化檢查結果位於 `outputs/TouchMiddle-0.3.0-beta.1-macos-arm64/`。本機產物不納入 Git。

# TouchMiddle 0.2.1-beta.1 候選包驗證

日期：2026-10-11（Asia/Taipei）。此記錄只代表本機候選包驗證，不代表已發布、已替換本機安裝版本或已完成其他 Mac 的安裝驗收。

## 已確認

- App 來源版本與解壓後 bundle 一致：0.2.1，build 3。ZIP 名稱含測試版標記 `0.2.1-beta.1`。
- 現有 Swift 測試 73 項通過，0 失敗（68 項核心測試、5 項登入項目狀態測試）。後者不是實際登入系統的端到端驗收。
- Release 建置成功；解壓後執行檔架構為 arm64。
- 解壓後 `codesign --verify --strict` 通過；簽章為 ad-hoc，無 Apple Developer ID、TeamIdentifier 或公證。
- ZIP 共 16 個項目，經白名單檢查；只有 App bundle、LICENSE、INSTALL.md、SIGNING.md、OPERATION.txt 與 RELEASE-NOTES.md 及所需目錄。不含個人規則或診斷。
- ZIP 的 LICENSE 與 App 內的 `Contents/Resources/LICENSE` 均與倉庫授權檔一致，作者為 ilovetai1。
- SHA-256 與 `SHA256SUMS.txt` 一致：`bdbdb3f85d55b0b8540b614cd7d1fecf1cf4415aaf8e38e7414e0123d2895b6e`。
- Shell 語法與 `git diff --check` 通過。發布前重跑 73 項 Swift 測試及 8 項版本工具測試，全部通過。

本次另加入 SIGNING.md 並更新安裝與版本說明後重新封裝；App 執行檔與前次逐位元相同，解壓後簽章檢查通過。此次文件更新未重新建置 App，也未變更本機憑證或權限。

## 尚未確認

- 「狀態與設定」新增資訊區塊已通過 Swift 編譯；原生畫面工具兩次回報 `Sky Computer Use native pipe closed before response`，未完成視覺驗收。
- 此候選 App 未啟動作手勢實機驗收，也未替換已安裝 App。0.2.0 歷史手勢結果不可視為新候選包的完整驗收。
- 其他 Mac 從 GitHub 下載後的 Gatekeeper／輔助使用安裝流程、其他硬體與 macOS 版本，以及登入自動啟動的實際登記／取消與重新登入尚未驗證。

原始建置／測試 log 保留於本機 `outputs/TouchMiddle-0.2.1-beta.1-macos-arm64/`；最終公開附件保留於 `outputs/TouchMiddle-0.2.1-beta.1-release/`，不納入 Git。最終包僅同步說明文件，App bundle 與使用者確認版本所有檔案逐位元一致。公開時附 ZIP、SHA256SUMS.txt 與 SIGNING.md。

## 發布狀態

使用者已確認並授權提交、推送、公開倉庫及發布測試版。發布目標為 `ilovetai1/TouchMiddle` 公開倉庫及 `v0.2.1-beta.1` Pre-release。

既有 Git 歷史包含作者姓名、公司信箱與舊本機路徑，將隨倉庫公開；此次未重寫 Git 歷史。目前 README 與操作說明已改成通用路徑。

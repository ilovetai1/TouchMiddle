# TouchMiddle 0.2.1-beta.1

GitHub Pre-release；採 MIT 授權，作者為 ilovetai1。App 內部版本為 0.2.1（build 3）。

## 內容

- 兩指／三指雙擊、三指輕點中鍵、快捷鍵錄製，以及全域與 App 專屬規則。
- 可選擇登入 macOS 時自動啟動；手勢每次啟動仍預設暫停。
- 「狀態與設定」新增作者 ilovetai1、GitHub 連結、MIT 授權條件與測試版限制。
- MIT 授權允許所有人使用、修改、散布及商業使用。

## 安裝包

`TouchMiddle-0.2.1-beta.1-macos-arm64.zip` 包含 App、安裝說明、操作說明與 MIT 授權。不包含個人規則、原始觸控資料或本機診斷。SHA-256 見同目錄的 `SHA256SUMS.txt`。

此包只適用 Apple Silicon。使用 ad-hoc 本機簽章，沒有 Apple Developer ID 憑證、Apple 公證或自動更新。首次開啟及權限步驟見安裝包的 `INSTALL.md`。

**簽章與權限提醒：** 本機自簽憑證也不等於 Apple Developer ID，不會讓其他 Mac 自動信任 App。更新後即使「輔助使用」開關亮著，也可能仍是舊 App 的授權；請結束 App、移除舊項目、加入固定安裝位置的新版 App，再重新啟動。完整說明見安裝包的 `SIGNING.md`；不需要關閉 Gatekeeper 或重設其他 App 的權限。

## 驗證範圍

當次自動測試與封裝檢查結果另記於倉庫 `docs/BETA-VERIFICATION.md`。歷史 0.2.0 實機結果見 `docs/VERIFICATION.md`，不代表此測試包已完成實機驗收。

尚未完成其他 Mac 上從 GitHub 下載後的首次安裝、登入自動啟動登記／取消與重新登入驗收；也未驗證 Intel、外接 Magic Trackpad、其他 macOS 版本、長時間使用、真實 sleep/wake 或任意掌心接觸。

使用 MultitouchSupport 私有 framework，系統升級後需重新驗證。可能漏判、誤觸或與 macOS 原生手勢同時觸發。事件送達不保證所有第三方 App 執行快捷鍵。

## 簽章處理說明與校驗

Release 附帶 `SIGNING.md` 與 `SHA256SUMS.txt`。請先查看簽章說明，再依需要處理首次開啟及新版輔助使用授權。SHA-256 用於檢查下載完整性，不代表 Apple 公證或安全保證。

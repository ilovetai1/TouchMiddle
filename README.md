# TouchMiddle

macOS 原生觸控板手勢與快捷鍵工具。支援兩指／三指雙擊、快捷鍵錄製，以及全域與 App 專屬規則；保留三指輕點中鍵功能。

作者：[ilovetai1](https://github.com/ilovetai1)。採用 [MIT 授權](LICENSE)，允許所有人使用、修改、散布與商業使用；散布時須保留版權與授權文字。軟體按現況提供，不附保固。

## 安裝測試版

公開測試版：**0.2.1-beta.1**，App 版本為 0.2.1。此版本仍有未完成的驗收項目，詳見下方限制。

可到 [GitHub Releases](https://github.com/ilovetai1/TouchMiddle/releases/tag/v0.2.1-beta.1) 下載 `TouchMiddle-0.2.1-beta.1-macos-arm64.zip`。安裝包適用 Apple Silicon Mac，不需要 Xcode。「Source code」ZIP 是原始碼，不是可直接開啟的 App。

1. 解壓縮，將 `TouchMiddle.app` 放入 `/Applications` 或 `~/Applications`。
2. 開啟 App。若 macOS 因無法驗證開發者而阻擋，確認來源可信後，依[安裝說明](docs/INSTALL.md)在「隱私權與安全性」手動允許。
3. 授予「輔助使用」權限；新增手勢規則，再開啟「啟用手勢」。每次重啟預設暫停。

沒有使用 Apple Developer ID 憑證或公證。公開測試包使用 ad-hoc 本機簽章；本機自用建置可使用固定的自簽憑證。兩者都不會取得 Apple 的開發者信任，也不會消除下載後的安全提示。

**權限開關已開，App 仍顯示未取得權限？** 更新或重新建置後，系統可能仍保留舊簽章的授權。請先結束 TouchMiddle，在「輔助使用」移除舊項目，加入目前安裝位置的新版 App，再重新啟動。詳見[簽章狀態與處理步驟](docs/SIGNING.md)，其中也說明本機自簽與 Apple 公證的差別。

[完整安裝、更新與移除說明](docs/INSTALL.md) · [手勢操作說明](touchmiddle/README.txt) · [測試版說明](docs/RELEASE-0.2.1-beta.1.md) · [0.2.0 歷史驗收](docs/VERIFICATION.md)

## 限制

- 套件宣告最低 macOS 14；實機驗收僅涵蓋 Apple M5、內建觸控板與 macOS 27.0.1。最低版本宣告不代表所有版本已測試。
- 此包僅含 arm64。Intel、外接 Magic Trackpad 與其他 macOS 版本尚未驗證。
- 使用 MultitouchSupport 私有 framework，macOS 升級後需重新驗證。
- 可能漏判或誤觸；不攔截 macOS 原生手勢，兩者可能同時觸發。不保證所有第三方 App 執行對應快捷鍵。
- 真實 sleep/wake、長時間壓力、任意掌心接觸與登入自動啟動的重新登入驗收尚未完成。
- 未加入上傳或自動更新服務，使用者自行從 Releases 更新。

## 從原始碼建置

需要 macOS、Xcode/Swift 6 與 `python3`；沒有外部 Swift 套件。從倉庫根目錄執行：

```bash
xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-tests
bash touchmiddle/Tools/build-app.sh --output "$HOME/Applications/TouchMiddle.app"
```

目的地必須尚未存在；建置不會替換現有 App、啟動 App、授予權限或登記登入項目。預設建置目前機器的架構。

本機有 `~/Library/Application Support/TouchMiddle/Signing/identity.json` 時，建置會使用其中的固定憑證 SHA-1 指紋；私鑰存於鑰匙圈。也可用 `--signing-identity SHA1` 或 `TOUCHMIDDLE_SIGNING_IDENTITY` 指定憑證。設定無效或憑證不存在時會中止，不會改用 ad-hoc。沒有本機設定時維持原有 ad-hoc 行為；`--ad-hoc` 可明確選擇此模式，測試版打包腳本固定使用它。

從 ad-hoc 改為憑證簽章後，需要重新授予輔助使用權限。之後維持同一憑證與 Bundle ID，可讓更新符合相同的簽章身分要求；權限是否保留仍需實機驗證。請保留憑證及私鑰，憑證重建或到期更換時重新驗證。

測試版打包指令：

```bash
bash touchmiddle/Tools/package-beta.sh --output "$PWD/outputs/TouchMiddle-0.2.1-beta.1-macos-arm64"
```

輸出目錄必須尚未存在；腳本只在本機建置、打包及產生 SHA-256，不會 push、公開倉庫或發布 Releases。

## 版本管理

目前原始碼版本：`0.2.1`；build：`3`。

採用 major／minor／patch 三段式版本規則，以 `touchmiddle/Tools/Info.plist` 為唯一來源。工具同步當期文件與 [CHANGELOG](CHANGELOG.md)，不自動 commit、tag 或 push。既有 beta 發布說明與歷史驗收保留原版號；新版本的發布包須另外準備。

```bash
./scripts/bump_version.sh current
./scripts/bump_version.sh minor "新增功能摘要" --dry-run
./scripts/bump_version.sh patch "修正摘要"
./scripts/check_version_consistency.sh
./scripts/check_version_consistency.sh --app /絕對路徑/TouchMiddle.app
```

完整規則見 [版本管理規範](docs/VERSIONING.md)。建置工具會在編譯前及產生 bundle 後執行一致性檢查。

## 目錄

- `touchmiddle/`：Swift 原始碼、測試與建置工具。
- `docs/`：安裝說明、版本說明與驗收摘要。
- `outputs/`、`work/`：本機產物與原始驗收資料，不納入 Git。

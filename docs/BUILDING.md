# 從原始碼建置

需要 macOS、Xcode/Swift 6 與 `python3`；沒有外部 Swift 套件。以下指令從倉庫根目錄執行。

## 測試與建置

```bash
xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-tests
bash touchmiddle/Tools/build-app.sh --output "$HOME/Applications/TouchMiddle.app"
```

目的地必須尚未存在；建置不會替換現有 App、啟動 App、授予權限或登記登入項目。預設建置目前機器的架構。

## 簽章

本機有 `~/Library/Application Support/TouchMiddle/Signing/identity.json` 時，建置會使用其中的固定憑證 SHA-1 指紋；私鑰存於鑰匙圈。也可用 `--signing-identity SHA1` 或 `TOUCHMIDDLE_SIGNING_IDENTITY` 指定憑證。設定無效或憑證不存在時會中止，不會改用 ad-hoc。沒有本機設定時維持原有 ad-hoc 行為；`--ad-hoc` 可明確選擇此模式，測試版打包腳本固定使用它。

從 ad-hoc 改為憑證簽章後，需要重新授予輔助使用權限。之後維持同一憑證與 Bundle ID，可讓更新符合相同的簽章身分要求；權限是否保留仍需實機驗證。請保留憑證及私鑰，憑證重建或到期更換時重新驗證。簽章狀態與權限處理見 [SIGNING.md](SIGNING.md)。

## 測試版打包

```bash
bash touchmiddle/Tools/package-beta-0.4.0.sh --output "$PWD/outputs/TouchMiddle-0.4.0-beta.1-macos-arm64"
```

輸出目錄必須尚未存在；腳本只在本機建置、打包及產生 SHA-256，不會 push、公開倉庫或發布 Releases。

## 版本管理

目前原始碼版本：`0.5.2`；build：`9`。

採用 major／minor／patch 三段式版本規則，以 `touchmiddle/Tools/Info.plist` 為唯一來源。工具同步當期文件與 [CHANGELOG](../CHANGELOG.md)，不自動 commit、tag 或 push。既有 beta 發布說明與歷史驗收保留原版號；新版本的發布包須另外準備。

```bash
./scripts/bump_version.sh current
./scripts/bump_version.sh minor "新增功能摘要" --dry-run
./scripts/bump_version.sh patch "修正摘要"
./scripts/check_version_consistency.sh
./scripts/check_version_consistency.sh --app /絕對路徑/TouchMiddle.app
```

完整規則見 [版本管理規範](VERSIONING.md)。建置工具會在編譯前及產生 bundle 後執行一致性檢查。

## 目錄

- `touchmiddle/`：Swift 原始碼、測試與建置工具。
- `scripts/`：版本工具及其測試。
- `docs/`：安裝說明、版本說明與驗收摘要。
- `outputs/`、`work/`：本機產物與原始驗收資料，不納入 Git。

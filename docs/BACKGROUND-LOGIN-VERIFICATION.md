# 登入背景啟動驗證

日期：2026-10-17（Asia/Taipei）。來源版本：0.5.2 / build 9。

登入啟動依 macOS 的 open-application Apple event 判斷；只初始化選單列、觸控控制器及更新排程，不開啟設定視窗。在使用者開啟設定或更新視窗前，自動更新查詢也不彈出視窗。手動啟動、再次開啟 App 與選單列操作仍可開啟視窗。登入項目的登記狀態與手勢辨識規則未修改。

判斷依據：[Apple keyAELaunchedAsLogInItem](https://developer.apple.com/documentation/coreservices/keyaelaunchedasloginitem)。

已確認：

- `xcrun swift test --package-path touchmiddle --scratch-path /tmp/touchmiddle-tests` 通過，exit 0；App 測試 25 項，0 失敗。新增 3 項涵蓋登入事件、手動啟動、缺少事件及其他事件類型。
- `build-app.sh --output /tmp/TouchMiddle-background-login-20261017.app` release 建置、版本一致性及固定本機簽章驗證通過，exit 0。
- `git diff --check` 通過。

未驗證：真實登出／重新登入後的背景啟動、視窗與焦點狀態，以及背景執行時的真人手勢。建置及事件描述符測試不代表重新登入的端到端驗收。

## 授權後的本機安裝

同日依使用者「安裝推到遠端」指示，將候選包安裝到 `/Users/chunghan/Applications/TouchMiddle.app`，並從固定路徑啟動。版本維持 0.5.2 / build 9，未另行發布 Release，也未變更系統登入項目。

- 新舊 App 的簽章延續檢查通過；程式碼雜湊不同，designated requirement 相容。
- 啟動程序 PID 5362；診斷 session `0AB031EE-963B-4CE4-8384-7639DC485D96` 顯示 `accessibility=true`、`postEventAccess=true`、`listenEventAccess=true`、`enabled=true`、`sourceRunning=1`、`ruleCount=6`。
- 安裝前後 `rules.json` SHA-256 相同：`1425ddd22e56ddfe9ac95e01bed62584eeeca1e8cfab75baa4af57ca3ed0ee8b`。
- 舊 App 與安裝紀錄保存在 Git 忽略的 `work/background-login-install-20261017-124052/`。

以上證明本機安裝及啟動狀態；未完成重新登入或真人手勢端到端驗收。

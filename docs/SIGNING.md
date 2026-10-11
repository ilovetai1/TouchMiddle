# 簽章、公證與輔助使用權限

## 此測試包的狀態

`0.2.2-beta.1` 公開測試包使用 **ad-hoc 臨時簽章**，沒有 Apple Developer ID 憑證，也沒有 Apple 公證（notarization）。簽章完整性檢查通過，不代表 Apple 已信任作者或已檢查 App 的安全性。

MIT 是原始碼使用與散布的授權，不會取代 macOS 的安全檢查，也不會自動授予輔助使用權限。GitHub 提供原始碼及安裝包下載，不會替 App 取得 Apple 信任。

## 三種方式的差別

| 方式 | 用途與限制 |
| --- | --- |
| ad-hoc 臨時簽章 | 此公開測試包使用的方式；不使用憑證。程式變更後，macOS 可能不再接受先前授權的 App 身分，需要重新授權。 |
| 固定的本機自簽憑證 | 可供開發者在自己的 Mac 持續使用同一簽章身分。不是 Apple Developer ID，不會讓其他 Mac 自動信任；能否保留更新前的輔助使用授權仍須實測。 |
| Apple Developer ID 與公證 | Apple 的對外發佈流程；本專案目前不採用。 |

作者本機的固定自簽憑證設定與對外測試包是不同的驗證範圍。不要假設作者本機能正常開啟，就代表下載到另一台 Mac 也能直接開啟。

## 首次開啟被阻擋

1. 確認安裝包來自 `ilovetai1/TouchMiddle` 的 GitHub Releases。可用同一 Release 的 `SHA256SUMS.txt` 檢查下載完整性；校驗碼不等於 Apple 公證或安全保證。
2. 將 App 放到固定安裝位置（`/Applications` 或 `~/Applications`），嘗試開啟一次。
3. 若提示無法驗證開發者或 Apple 無法檢查 App，在確認來源可信後，到「系統設定 → 隱私權與安全性」選擇「仍要打開」（Open Anyway），再依系統提示確認。
4. 若沒有此選項，確認是否為組織管理的 Mac；管理政策可能禁止允許例外。不要關閉整台 Mac 的 Gatekeeper 來安裝。
5. 若提示含惡意軟體、會損害電腦或 App 已損毀，停止使用並重新確認下載來源與校驗結果，向專案回報完整提示。不要把這類警告當成一般的開發者驗證提示略過。

依據：[Apple：安全地開啟 Mac App](https://support.apple.com/en-au/102445)。介面文字可能因 macOS 版本或語言不同而變動。

## 開關已開，App 仍說未取得輔助使用權限

更新、重新建置或改簽章後，系統可能保留舊 App 的授權項目，但目前執行版本不符合舊身分。開關亮著不保證目前 App 已獲准。這與首次開啟的 Gatekeeper 提示是兩項不同檢查。

1. 從 TouchMiddle 選單列選「結束 TouchMiddle」，並確認沒有另一份 TouchMiddle 正在執行。
2. 開啟「系統設定 → 隱私權與安全性 → 輔助使用」。
3. 選取舊的 TouchMiddle 項目，按「−」移除；按「＋」加入固定安裝位置的新版 `TouchMiddle.app`，再開啟權限。只操作 TouchMiddle，不需要重設其他 App 的授權。
4. 從剛加入的同一路徑重新啟動 App，到「狀態與設定」確認「輔助使用權限已允許」。
5. 若仍未取得權限，記下 App 版本、macOS 版本、安裝位置、系統提示與 App 顯示狀態，再向 [GitHub Issues](https://github.com/ilovetai1/TouchMiddle/issues) 回報。回報前移除診斷中的個人路徑或其他敏感資訊。

重新加入權限不需要刪除 `rules.json`。授權後仍須實際測試規則；權限允許不保證第三方 App 已執行快捷鍵。

此流程用於排除舊授權身分不匹配；不能保證解決所有權限問題，也不能由 App 自動替使用者授權。

## 自行建置與本機自簽

使用同一固定憑證、私鑰、Bundle ID 與相容的簽章要求，有助於讓系統辨認更新前後的 App；憑證遺失、重新建立或簽章要求改變，可能仍需重新授權。不承諾永久保留輔助使用權限。

此測試包不要求下載者建立憑證、安裝作者的憑證或更改鑰匙圈信任。自行建置若選用本機自簽，應保護自己的私鑰，不提交到 Git、不放進 Release，也不分享給其他使用者。

依據：[Apple：Code Signing Requirements（TN3127）](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)；[Apple：建立自簽憑證](https://support.apple.com/guide/keychain-access/create-self-signed-certificates-kyca8916/mac)。

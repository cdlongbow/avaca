# AVACA 0.8.4

## 更新內容

- 泛化作品番號正規化與跨來源去重；例如 `1start00023` 與 `START-023`、
  `1stzy00017` 與 `STZY-017` 會合併為同一個最正規的 `英文-數字` 番號，
  同時避免不同數字核心被誤合併。
- 修正 Minnano AV 直接演員頁面無法刮削的問題；像「河北彩花」會透過安全的
  canonical profile link 正確解析，並保留演員名稱清理與結果去重。
- Windows portable 更新改用原生 `avaca_update.exe` helper，加入 ZIP 驗證、
  路徑穿越防護、啟動確認與失敗回復，不影響 `%LOCALAPPDATA%\AVACA` 使用者資料。
- 補充跨來源番號、Minnano 直接 profile、Windows 更新封裝與安全性測試。

## Release 資產

- `avaca-0.8.4-arm64-v8a.apk`
- `avaca-0.8.4-arm64-v8a.apk.sha256`
- `avaca-0.8.4.zip`
- `avaca-0.8.4.zip.sha256`

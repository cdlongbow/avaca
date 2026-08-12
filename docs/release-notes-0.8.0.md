# AVACA 0.8.0

## 更新內容

- 新增「設定 > 其他 > 軟體更新」，顯示目前版本與最新版本。
- 新增自動檢查更新開關與手動「檢查更新」按鈕；找到新版本後可在彈窗直接開始更新。
- Android 會從 GitHub Release 下載 ARM64 APK，並交由系統安裝程式完成更新。
- Windows 使用 portable ZIP 更新，只替換應用程式資料夾，不搬移或覆寫 `%LOCALAPPDATA%\AVACA` 的資料庫與圖片。
- 更新完成後清除應用程式快取；Windows 更新失敗時會嘗試復原原本的程式檔案。
- Works 新增作品編號搜尋，並補強設定與作品頁的響應式 UI 測試。
- Release 資產固定使用版本化檔名，並驗證 SHA-256；Android `versionCode` 使用 GitHub Actions `run_number` 遞增。

## Release 資產

- `avaca-0.8.0-arm64-v8a.apk`
- `avaca-0.8.0-arm64-v8a.apk.sha256`
- `avaca-0.8.0.zip`
- `avaca-0.8.0.zip.sha256`

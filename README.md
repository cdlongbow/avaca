# AVACA

AVACA 是一個以本地資料為主的女優與作品收藏 App。

## Windows portable 版

Windows portable release 會包含完整的 Flutter 執行檔 bundle，以及
update.cmd 更新命令。將 ZIP 解壓到想使用的資料夾後，直接執行：

    .\update.cmd

這會取得最新的正式 GitHub Release，下載對應版本的
avaca-X.Y.Z.zip，驗證版本與 avaca.exe 後替換
portable 程式檔。也可以指定版本：

    .\update.cmd 0.8.0

更新命令會在替換程式前停止 AVACA，失敗時復原原本的程式 bundle，成功
後重新啟動 App。AVACA Windows 版的資料庫、圖片與設定位於：

    %LOCALAPPDATA%\AVACA

更新器不會刪除、搬移或覆寫這個資料夾，也不要求重新匯出或匯入收藏資料。
請先關閉其他正在使用 AVACA 資料的程序，再執行更新。

若只想先下載、解壓與驗證而不替換檔案，可使用：

    .\update.cmd latest -WhatIf

## Release artifacts

完整的 Release 命名、Android versionCode 與 portable 內容規則請看
[`docs/release.md`](docs/release.md)。推送符合 `vX.Y.Z` 的 tag 後，GitHub
Actions 會驗證 tag 與 `pubspec.yaml` 版本一致，並且只建立以下四個固定命名
的上傳資產：

- `avaca-X.Y.Z-arm64-v8a.apk`
- `avaca-X.Y.Z-arm64-v8a.apk.sha256`
- `avaca-X.Y.Z.zip`
- `avaca-X.Y.Z.zip.sha256`

例如 `v0.8.0` 的資產名稱必須是
`avaca-0.8.0-arm64-v8a.apk`、`avaca-0.8.0-arm64-v8a.apk.sha256`、
`avaca-0.8.0.zip` 和 `avaca-0.8.0.zip.sha256`。Android 的
`versionCode` 由 workflow 使用 `GITHUB_RUN_NUMBER + 25`，從 30 開始；正式發布時
必須比上一版大。

Android release signing 使用 GitHub Actions secrets，不會把 keystore 或
密碼提交到 repository。需要設定：

- ANDROID_KEYSTORE_BASE64
- ANDROID_KEYSTORE_PASSWORD
- ANDROID_KEY_ALIAS
- ANDROID_KEY_PASSWORD

# AVACA

AVACA 是一個以本地資料為主的女優與作品收藏 App。

## Windows portable 版

Windows portable release 會包含完整的 Flutter 執行檔 bundle，以及
update.cmd 更新命令。將 ZIP 解壓到想使用的資料夾後，直接執行：

    .\update.cmd

這會取得最新的正式 GitHub Release，下載對應版本的
avaca-X.Y.Z.zip，驗證版本與 avaca.exe 後替換
portable 程式檔。也可以指定版本：

    .\update.cmd 0.7.10

更新命令會在替換程式前停止 AVACA，失敗時復原原本的程式 bundle，成功
後重新啟動 App。AVACA Windows 版的資料庫、圖片與設定位於：

    %LOCALAPPDATA%\AVACA

更新器不會刪除、搬移或覆寫這個資料夾，也不要求重新匯出或匯入收藏資料。
請先關閉其他正在使用 AVACA 資料的程序，再執行更新。

若只想先下載、解壓與驗證而不替換檔案，可使用：

    .\update.cmd latest -WhatIf

## Release artifacts

推送符合 vX.Y.Z 的 tag 後，GitHub Actions 會驗證 tag 與
pubspec.yaml 版本一致，並建立：

- avaca-X.Y.Z-arm64-v8a.apk
- avaca-X.Y.Z.zip

Android release signing 使用 GitHub Actions secrets，不會把 keystore 或
密碼提交到 repository。需要設定：

- ANDROID_KEYSTORE_BASE64
- ANDROID_KEYSTORE_PASSWORD
- ANDROID_KEY_ALIAS
- ANDROID_KEY_PASSWORD

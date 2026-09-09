# AVACA Release 發布規則

這份文件是 AVACA 發布 GitHub Release 的命名與版本契約。
實際發布由 [`.github/workflows/release.yml`](../.github/workflows/release.yml)
執行；不符合以下規則時，workflow 必須失敗，不得發布不規則的資產。

## 版本與 Tag

- Release Tag 必須是 `vX.Y.Z`，例如 `v0.8.1`。
- Tag 的 `X.Y.Z` 必須與 `apps/avaca/pubspec.yaml` 與
  `apps/server/pubspec.yaml` 的版本完全一致；兩個 app 的完整版本與
  Android build number 也必須相同。根目錄 `pubspec.yaml` 是 migration
  fixture，不是正式產品的建置來源。
- 只發布正式版，不使用 draft 或 prerelease 資產。
- Android 的 `versionName` 使用 `X.Y.Z`。
- `v0.8.0` 的歷史 APK 使用 `versionCode=30`；`v0.8.1` 使用
  `versionCode=2026`；`v0.8.2` 使用 `versionCode=2027`。`v0.8.1` 之後，
  每個正式版本的 workflow 都使用 `pubspec.yaml` 的完整
  `X.Y.Z+versionCode` build metadata，並驗證 `versionCode` 至少為 30。
  Android 不接受較小或重複的 `versionCode` 作為更新。
- 同一個 Tag 重新執行 workflow 會保留相同的 `versionCode`，只能更新同一個
  GitHub Release；要發布新版本，必須使用新的 `vX.Y.Z` Tag 並先提高
  `pubspec.yaml` 的 build metadata。

## GitHub Release 資產檔名

Release 中的上傳資產必須且只能使用下列六個檔名。`X.Y.Z` 取自 Release
Tag 去掉開頭的 `v`：

| 平台 | 正式資產 | SHA-256 sidecar |
| --- | --- | --- |
| Android ARM64 AVACA | `avaca-X.Y.Z-arm64-v8a.apk` | `avaca-X.Y.Z-arm64-v8a.apk.sha256` |
| Windows x64 AVACA client | `avaca-X.Y.Z.zip` | `avaca-X.Y.Z.zip.sha256` |
| Windows x64 AVACA Server | `avaca-server-X.Y.Z.zip` | `avaca-server-X.Y.Z.zip.sha256` |

例如 `v0.8.1` 必須產生：

```text
avaca-0.8.1-arm64-v8a.apk
avaca-0.8.1-arm64-v8a.apk.sha256
avaca-0.8.1.zip
avaca-0.8.1.zip.sha256
avaca-server-0.8.1.zip
avaca-server-0.8.1.zip.sha256
```

命名要求：

- 使用小寫 `avaca`。
- 版本使用完整三段 SemVer：`major.minor.patch`。
- 使用連字號 `-`，不使用空白、底線、日期或 `latest`。
- Android 架構固定寫成 `arm64-v8a`。
- Windows 資產固定使用 `.zip`，不加入額外架構字串。
- checksum 檔名必須是原資產檔名再加上 `.sha256`。
- 不上傳 `app-release.apk`、`avaca.zip`、未帶版本的檔案或其他替代命名。

GitHub Release 自動產生的 source code archive 不屬於上述上傳資產；本契約只管 workflow 上傳的四個檔案。

## Windows portable 內容

`avaca-X.Y.Z.zip` 是 AVACA 用戶端，解壓後必須包含完整 Windows Flutter
bundle，以及：

- `avaca.exe`
- `version.txt`，內容必須是 `X.Y.Z`
- `msquic.dll`、`avaca_remote_quic.dll` 與 pinned MsQuic provenance
- player runtime closure 與其授權/來源資料

`avaca-server-X.Y.Z.zip` 是獨立的 AVACA Server，解壓後必須包含：

- `avaca_server.exe`
- `version.txt`，內容必須是 `X.Y.Z`
- `msquic.dll`、`avaca_remote_quic.dll` 與 pinned MsQuic provenance
- 不得包含 `avaca.exe`、`libmpv-2.dll`、`libEGL.dll`、`libGLESv2.dll` 或
  其他 player runtime。

AVACA client 與 AVACA Server 是分離的 portable products；資料庫與圖片位於
各自的 app-private data directory，不在 ZIP 替換範圍內。

## 發布方式

1. 同步更新根目錄 migration fixture、`apps/avaca` 與 `apps/server` 的
   `X.Y.Z+versionCode`；正式 app 版本必須一致。
2. 確認 Android `versionCode` 會遞增。
3. 建立並推送對應的 `vX.Y.Z` Tag。
4. 由 `release.yml` 建立資產、checksum 並發布 GitHub Release。
5. 發布前的 workflow 檢查必須通過；不要手動改名或補上不符合規則的資產。

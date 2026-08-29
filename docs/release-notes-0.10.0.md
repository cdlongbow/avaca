# AVACA 0.10.0

## 更新內容

- 新增可攜式媒體庫匯入與維護流程，包含可恢復的匯入 journal、媒體中繼資料、可攜式識別碼與失敗恢復。
- 新增跨平台播放器介面與 Android／Windows 原生播放整合，並提供播放跳轉秒數與暫時播放速度設定。
- 新增隔離的遠端連線核心，包含認證 session、憑證釘選、QUIC channel binding，以及明確 opt-in 的 Windows MsQuic 邊界。
- 重新整理來源 identity、provenance、圖片路由、資料健康檢查與作品列表，以配合媒體庫與播放流程。

## 驗證與發行資產

正式發行資產由 tagged GitHub Actions workflow 產生並驗證，固定包含：

- `avaca-0.10.0-arm64-v8a.apk`
- `avaca-0.10.0-arm64-v8a.apk.sha256`
- `avaca-0.10.0.zip`
- `avaca-0.10.0.zip.sha256`

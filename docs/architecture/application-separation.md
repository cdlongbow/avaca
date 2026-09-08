# AVACA 應用分離契約

## 應用邊界

- **AVACA Server**：僅 Windows。唯一擁有 Library、scraper、catalog、媒體路徑解析與播放授權的程序，執行 `apps/server`，輸出 `avaca_server.exe`。
- **AVACA**：Windows + Android。負責瀏覽、搜尋、詳情、播放 UI 與 QUIC client，執行 `apps/avaca`，Windows 輸出 `avaca.exe`。
- 根目錄的舊 Flutter target 僅保留作 migration fixture；其 `main()` 只顯示導引殼，不開啟舊 DB、remote 或 player。兩個新 production app 不匯入 `package:avaca/` 的 Library 或 scraper。

## 協定 v2

`packages/avaca_protocol` 是唯一 wire contract。Frame opcode 使用明確稀疏值（例如 `readResource=0x42`、`createPlaybackSession=0x30`），不使用 enum index。ALPN、TLS exporter、pre-auth、discovery、namespace、pairing transcript 全部固定為 v2，拒絕 v1 downgrade。

所有 Media/Work ID 都是不透明的 16-byte portable ID。路徑、SQL integer PK、UNC 或 token 不會進入 catalog payload。

## 播放資料流

Server 以 memory-only `PlaybackGrantRegistry` 建立短期 grant；`ServerMediaResourceService` 是唯一讀檔者。AVACA 取得 descriptor 後交給 `avaca_remote_playback_*` 原生 ABI；Windows player 已將 `avaca-quic` 的 libmpv `mpv_stream_cb_*` seam 接到 pinned MsQuic range adapter，Android 則透過同一份 v2 frame/HMAC/exporter core 接到 Media3 `DataSource`。兩端都提供 blocking range read、absolute seek、cancel 與 close；native bridge 未建立或 descriptor 不完整時 fail closed，沒有 HTTP、SMB、整檔下載、暫存檔或 Dart media-byte proxy fallback。

## Windows bundle 規則

`tooling/verify_windows_bundle.ps1`：

- Server 必須有 `avaca_server.exe`，且不得包含 `libmpv-2.dll`、ANGLE、`avaca_player_native.dll`。
- AVACA 必須有 `avaca.exe` 與 player runtime。
- MsQuic 只有在 exact source commit、建置 DLL 與 provenance manifest 都通過後才可開啟。

## 匯入順暢度修正

1. Review 產生的 immutable plan 在 Commit 直接重用；只套用使用者選取的 primary performer，不重新 scrape、ffprobe 或 hash。
2. SHA-256 `hashFile` 放到 worker isolate，避免大型檔案佔用 Flutter UI isolate。
3. `LibraryOperationGate` 的 queue 與跨程序 file lock 都有 10 秒等待上限，超時回傳 `LIBRARY_OPERATION_BUSY`，UI 可安全重試。
4. plan revision、root 與 source snapshot 不符時回傳 `PLAN_STALE`，不會在背景重建或卡死；journal/cleanup 狀態仍可供 recovery。

## Server 匯入 composition

`apps/server` 的 runtime 可注入 `AvacaScraper`，並將其與 Server-owned
`ServerCatalogWriter` 組成 `ServerFolderImportService`。匯入面板只在使用者按下
「開始匯入」後啟動非同步掃描；進度以 16ms 節流更新，關閉視窗會先取消再等待
item 邊界，避免 DB close 與寫入競態。掃描結果會回報 scanning／resolving／indexing
三段耗時與 imported/skipped/failed 數量。

目前沒有把 root scraper providers 偷塞進 Server；Server production composition
仍需注入真正的 `AvacaScrapeSource`。未注入時不會用 hardcoded 或 always-success
資料冒充匯入，面板會明確顯示尚未啟用。

## Windows 啟動 composition

`apps/server` 與 `apps/avaca` 都先繪製管理／瀏覽殼，再由 state lifecycle
非同步建立資料庫或 authenticated QUIC transport。Windows Server 透過
`AVACA_SERVER_*` 環境變數讀取 server id、listen port、憑證 thumbprint 與
pairing secret；Windows AVACA 透過 `AVACA_SERVER_*`／`AVACA_CLIENT_ID` 讀取
對端設定。環境值會做嚴格 hex 長度與 port 檢查，未完成時保持離線殼，不會
猜測憑證、把 secret 寫入 catalog，或在 `build`／首幀同步啟動網路。

這已完成 composition、原生 data-plane 接線與 build 邊界；仍不等同於真實
Server→AVACA→native player playback、seek、stop 實機驗收已通過。實機與
action-level UI evidence 仍須以同一 final candidate 收集。

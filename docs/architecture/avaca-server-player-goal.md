# AVACA Server / AVACA 分離 Goal

**Operation ID**：`avaca-server-player-connection-20260908-7k2m`

## 目標

在同一個 Git repository 內維持一個 AVACA 產品，但拆成兩個獨立的 runtime：

- **AVACA Server**：只支援 Windows，擁有 Library、匯入／刮削、catalog、實體媒體路徑、播放授權與 QUIC listener。
- **AVACA**：支援 Windows 與 Android，只負責 Server discovery／連線、Library 瀏覽、詳情與播放 UI；不讀 Server DB，也不接觸 Server 實體路徑。

舊 Library 與舊功能目前尚未正式使用，這次不刪除、不 migration、不清空資料；它們只保留作為 migration fixture，新的 Server schema 使用獨立 `server_*` 表。

## 不凍結流程的硬性規則

1. widget `build` 不啟動網路、資料庫、scanner、scraper 或播放器。
2. Review 完成的 immutable import plan 在 Commit 直接重用，不重跑 scrape、ffprobe 或整檔 hash。
3. SHA-256 放在 worker isolate；Library queue 與跨程序 lock 等待有上限，超時回傳 `LIBRARY_OPERATION_BUSY`。
4. 匯入進度每個 frame 最多發佈一次，避免大量檔案的 progress callback 佔滿 UI rebuild。
5. Commit 忙碌時提供取消；取消只在下一個 item 的 portable commit 前生效，保留 journal／來源檔，不切斷半份檔案操作。
6. playback resource 對每個 session 重新產生 opaque ID；關閉 session 立即關閉對應檔案與 grant。
7. 導覽使用保留頁面狀態的短動畫；連線／catalog 工作由 application host 管理，不在切頁 callback 中執行。
8. Server 與 AVACA 都以 async bounded session／frame channel 傳輸；錯誤只回傳穩定 code，不回傳路徑、token 或 stack trace。
9. Collection／Detail 圖片 build 不做 `existsSync`；由非同步 image provider 與 `errorBuilder` 處理缺檔，避免卡住 frame isolate。

## 已完成的可驗證項目

- `apps/server` 與 `apps/avaca` 是獨立 Flutter entrypoint；Server 沒有 Android target，也不連結 `avaca_player_native`。
- shared package：`avaca_domain`、`avaca_protocol`、`avaca_remote_core`；Server package：`avaca_library`、`avaca_scraper`；Player package：`avaca_client`、`avaca_player_native`。
- protocol v2 使用顯式 sparse opcode、bounded DTO、opaque resource／work IDs。
- Server SQLite 使用 `server_works`／`server_media`，並有 catalog paging、detail、playback grant／range read vertical slice 測試。
- Android build 固定收斂到 `arm64-v8a` 與 `x86_64`，固定 phone/tablet AVD 名稱保留給 action-level 驗收；APK build 不等同於手機播放通過。
- Root import UI 已加入 progress coalescing、Review→Commit service reuse 與可取消的 Commit；新增 session 隔離測試避免多裝置互相關閉 playback。
- Server 管理殼會先 render 首幀，再於 state lifecycle 非同步開啟 `AVACA_SERVER_DB`；資料庫啟動不再阻塞 Windows `runApp`。
- Server 與 AVACA Windows composition 可由嚴格驗證的環境變數啟用；兩端在首幀後才建立 authenticated QUIC transport，缺少憑證／secret／MsQuic DLL 時只顯示可恢復狀態，不阻塞管理或瀏覽殼。
- Server resource open 對同一 opaque grant 具 reference-counted handle；Dart control lease 暫時斷線時，仍持有的 native lease 會保留 playback session，最後一條 lease 關閉後才撤銷 grant，並由 package test 覆蓋。
- Server 新增 Windows-only `ServerFolderImportService` 與管理面板：掃描、解析、索引各階段都有可觀測時間／進度，檔案上限不會靜默截斷，取消只在 item 邊界生效；runtime 會把 import、listener 與 close 串行化。
- `avaca_scraper` 提供 Server-owned `CompositeAvacaScraper` composition seam；來源失敗會隔離並回傳穩定錯誤，不把 scraper、cookie 或原始回應帶到 AVACA。
- `avaca_client` 新增 authenticated v2 browse/detail/play/range-seek/stop contract fixture test；fixture 僅存在測試，不進入 production transport composition。
- Windows AVACA client composition 會在首幀後讀取 server host／port／ID／certificate／pairing secret，建立真實 native transport；組態不完整或 listener 啟動失敗時維持 offline shell。Windows libmpv stream adapter 與 Android Media3/JNI MsQuic range adapter 已接線並可建置。
- 根目錄 Collection／Detail 圖片移除 build-time synchronous filesystem probe；受影響的 adaptive/Works/Detail/import UI regression 全部通過。
- 根目錄舊 Flutter target 已退役為 migration fixture 導引殼；啟動時不再開啟舊 DB、remote service 或 player/library monolith，舊 `AvacaApp` 類別與資料仍保留供 fixture 測試。

## 尚未宣稱完成的 Gate

- Windows／Android 的 native MsQuic playback data-plane adapter 已接上 libmpv／Media3 range seam，但本候選仍未完成真實 Server↔AVACA authenticated browse/detail/play/seek/stop playback evidence。
- Windows Server↔AVACA 的 listener／client 實機 action 尚未在本環境完成；目前可宣稱的是 composition、strict environment parsing、native build 與 in-memory authenticated contract evidence。
- 新 application session 的候選 pairing proof 尚未與 root production Ed25519 identity transcript 完成收斂，不能當作最終安全協定通過。
- 既有 root scraper providers 尚未搬入新 Server composition；目前 Server import 已完成真實 Windows filesystem scanner、bounded progress/cancel 與 catalog writer 接線，但必須由 production composition 注入實際 `AvacaScrapeSource`（未注入時匯入按 fail-closed 顯示未設定），root app 仍是 migration fixture。
- Android native remote transport 已接線並完成 APK／CMake build；phone/tablet 掃描或貼上 invitation、browse、play、seek、stop 的 action-level evidence 尚未完成。
- Windows compact／expanded／live resize／鍵盤與 Android touch/back/overflow 的 action-level UI gate 受 Computer Use trusted RPC（`sky` 未設定）阻擋，不能以靜態檢查代替 `PASS_UI`。
- External Sol final review／Gate 2 證據尚未附著到本候選，不能以本地測試或建置取代。

## 驗收順序

1. 先完成 Server import／scraper composition 與既有資料讀取適配，不碰舊資料內容。
2. 收斂 protocol/auth 與真實 MsQuic playback adapter，再做 Windows Server↔AVACA browse/detail/play/seek/stop vertical slice。
3. 在可觀測的 Windows、Android phone、Android tablet 環境收集 action-level UI、frame timings、import stage timings。
4. 只有所有必要 gate 均有同一候選 revision 的證據，才可將 Goal 標記完成；本次不 commit、tag、push 或 release。

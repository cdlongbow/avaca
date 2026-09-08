# AVACA Remote Connectivity Core：Windows MsQuic

這裡提供 Server 與 AVACA Windows composition 共用的可選 QUIC transport
邊界。預設 build 不會猜測憑證或載入任意 DLL；只有明確提供 MsQuic source／
runtime DLL 並在程序環境設定 authenticated pairing 值時，兩個 app 才會在
首幀後建立 listener／client transport。未設定或啟動失敗時保留可操作的
管理／瀏覽殼，不會替換成 plaintext、HTTP、SMB 或整檔下載。

## Native dependency

目前 bridge 對應官方 MsQuic v2.6.0（commit
`e7e7a114e20a55ec2d5f723cf6bdf3bfb7b0b24a`），Windows build 使用 Schannel。
MsQuic 必須由明確指定的 source/build 目錄提供；bridge 不會從 PATH、任意
DLL 或網路位置載入依賴。

先建立官方 MsQuic shared DLL，再以 AVACA 的 Windows CMake option opt in：

```powershell
cmake -S apps/server/windows -B apps/server/build/windows/x64 `
  -G Ninja -DCMAKE_BUILD_TYPE=Release `
  -DAVACA_MSQUIC_ROOT=D:/path/to/msquic `
  -DAVACA_MSQUIC_DLL=D:/path/to/msquic/build/windows/bin/Release/msquic.dll `
  -DAVACA_REMOTE_QUIC_ENABLED=ON
cmake --build apps/server/build/windows/x64 --config Release --target avaca_remote_quic_core
```

`AVACA_REMOTE_QUIC_ENABLED` 預設為 `OFF`。啟用時，CMake 會要求
`AVACA_MSQUIC_ROOT/src/inc/msquic.h` 與指定的 `AVACA_MSQUIC_DLL` 都存在，並
將 bridge DLL 與同一個明確指定的 `msquic.dll` 放到 app bundle 旁。完整 app
build 仍需照專案既有的 Flutter/FFmpegKit prerequisites 執行。

## Certificate and channel binding

- server certificate 使用 Windows Current User\My certificate store 中的
  SHA-1 thumbprint；沒有 server thumbprint 就不能開 listener。
- client 不使用 `NO_CERTIFICATE_VALIDATION`。它要求 Schannel portable
  certificate callback，對 server leaf DER 計算 SHA-256 並比對 pinned hash。
- QUIC TLS exporter `EXPORTER-AVACA-REMOTE-V2` 產生 32-byte channel binding。
  Pairing/auth transcript 同時包含 `RemoteLimits.protocolVersion` 與完整
  channel binding，換 socket、換 TLS session 或換 binding 都必須重新驗證；
  protocol v1 不會被接受或自動降級。
- ALPN 固定為 `avaca-remote/2`；native send/receive、Dart connection 與
  auth frame 都有既定上限。Frame opcode 使用 `avaca_protocol` 的顯式稀疏
  值，不依賴 enum declaration order。

沒有提供 plaintext TCP、accept-all TLS、arbitrary certificate fallback 或
自動憑證 provisioning。`apps/server` 的 `AvacaServerEnvironmentConfig` 與
`apps/avaca` 的 `AvacaClientEnvironmentConnection` 會嚴格檢查 ID、port、
thumbprint 與 secret 長度，然後把組態交給 `AvacaMsQuicTransportFactory`。
每次新連線會先以 QUIC channel binding 完成 pair-scoped pre-auth 與 mutual
auth，才交給 v2 application handler；缺少任一設定時不會降級。

目前 Windows native bridge 已把同一份 authenticated playback descriptor 接到
libmpv `mpv_stream_cb_*`；`openResource` 取得的 opaque handle、absolute
`readAt`、seek、cancel 與 close 都留在 native data-plane。Android 使用同一份
frame/HMAC/exporter core，透過 JNI 接到 Media3 `DataSource`，只允許
`arm64-v8a`／`x86_64` 的官方 MsQuic build。

Android 在 Windows host 上需要 Git-for-Windows Perl；應用程式 CMake 會在
build tree overlay 修正 upstream quictls 的 POSIX environment command，並只
提供 build-time localization shim，不修改 pinned MsQuic checkout。NDK r28c
目前最高可用 native API level 為 35，因此 compileSdk 36 的完整 Gradle／實機
驗收仍須以相容的 Android toolchain 完成，不能把 syntax-only 或 CMake
configure 當成手機播放通過。

配對資料由 `AVACA-PAIR-V2.` canonical base64url invitation 匯入；Windows
certificate store UI 只回傳 subject、SHA-1 thumbprint 與 leaf SHA-256 pin，
private key 不會離開 store。Player profile 由 Windows DPAPI 或 Android
Keystore/AES-GCM 保存。Windows DNS-SD 與 Android `NsdManager` 已接到原生
discovery channel；TXT 仍只提供 candidate，不攜帶 secret，也不會自動建立信任。
Android camera QR／貼上 invitation、Server→Player→native 實機端到端播放與
Windows／Android action-level UI 證據仍是獨立的驗收閘門，未完成前不得標記
`PASS_UI`。

## Windows native range E2E runner

`tooling/remote_server_player_e2e.dart` 是可重跑的 Windows runtime runner：它
啟動 `AvacaServerApplicationHost`，用真實 MsQuic DLL 建立 Dart control session，
再用同一 `clientId` 呼叫 native `avaca_remote_playback_open_native` 建立第二條
data-plane session，驗證 browse／detail、range／absolute seek、control disconnect
後的 native lease，以及 client reconnect。它只驗證 opaque range bytes，不會啟動
libmpv 視窗，因此不能取代實機播放與 UI gate。

```powershell
dart compile exe tooling/remote_server_player_e2e.dart `
  -o .codex-tmp/avaca_remote_server_player_e2e.exe
Copy-Item apps/server/build/windows/x64/runner/Debug/avaca_remote_quic*.dll `
  .codex-tmp/
Copy-Item apps/server/build/windows/x64/runner/Debug/msquic.dll .codex-tmp/
& .codex-tmp/avaca_remote_server_player_e2e.exe <sha1-40-hex> <leaf-sha256-64-hex> 45887
```

`<sha1-40-hex>` 必須是 Windows `CurrentUser\My` 中含 private key 的 Server
certificate thumbprint；`<leaf-sha256-64-hex>` 必須由同一張 leaf DER 計算。測試
結束後應刪除暫存 fixture 與測試憑證。

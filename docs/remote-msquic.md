# AVACA Remote Connectivity Core：Windows MsQuic spike

這一階段只提供可選的 Windows QUIC transport 邊界，供後續 service/auth
orchestration 接線使用。`RemoteServiceCoordinator.forApp()` 仍維持
`UnavailableRemoteTransport`，因此預設 build 不會載入 native bridge，也不會
啟用遠端播放器、媒體路徑、DHT、STUN/NAT 或 relay。

## Native dependency

目前 bridge 對應官方 MsQuic v2.6.0（commit
`e7e7a114e20a55ec2d5f723cf6bdf3bfb7b0b24a`），Windows build 使用 Schannel。
MsQuic 必須由明確指定的 source/build 目錄提供；bridge 不會從 PATH、任意
DLL 或網路位置載入依賴。

先建立官方 MsQuic shared DLL，再以 AVACA 的 Windows CMake option opt in：

```powershell
cmake -S windows -B build/windows/remote_quic_cmake `
  -G Ninja -DCMAKE_BUILD_TYPE=Release `
  -DAVACA_MSQUIC_ROOT=D:/path/to/msquic `
  -DAVACA_MSQUIC_DLL=D:/path/to/msquic/build/windows/bin/Release/msquic.dll `
  -DAVACA_REMOTE_QUIC_ENABLED=ON
cmake --build build/windows/remote_quic_cmake --target avaca_remote_quic
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
- QUIC TLS exporter `EXPORTER-AVACA-REMOTE-V1` 產生 32-byte channel binding。
  Pairing/auth transcript 同時包含 `RemoteLimits.protocolVersion` 與完整
  channel binding，換 socket、換 TLS session 或換 binding 都必須重新驗證。
- ALPN 固定為 `avaca-remote/1`；native send/receive、Dart connection 與
  auth frame 都有既定上限。

這個 spike 沒有提供 plaintext TCP、accept-all TLS、arbitrary certificate
fallback 或自動憑證 provisioning。`RemoteServiceCoordinator.forApp()` 仍是
安全的 unavailable composition；要啟用 production path，呼叫端必須使用
`forConfiguredApp()` 或 `forWindowsMsQuic()` 明確提供 endpoint/discovery
providers、certificate pin、server thumbprint、固定 listen port，以及
authenticated session handler。每次新連線會先以 QUIC channel binding 完成
pair-scoped pre-auth 與 mutual auth，才交給 handler；缺少任一設定時不會
替換成 plaintext 或 accept-all fallback。

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef QUIC_API_ENABLE_PREVIEW_FEATURES
#define QUIC_API_ENABLE_PREVIEW_FEATURES
#endif

#include "remote_quic_bridge.h"

#include <windows.h>
#include <bcrypt.h>
#include <objbase.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

#include <msquic.h>

namespace {

constexpr uint32_t kChannelBindingLength = 32;
constexpr uint64_t kMaxBufferedBytes = 16ull * 1024ull * 1024ull;
constexpr uint32_t kMaxReceiveBytes = 16u * 1024u * 1024u;
constexpr char kAlpn[] = "avaca-remote/1";
constexpr char kExporterLabel[] = "EXPORTER-AVACA-REMOTE-V1";

struct AvacaRemoteQuicTransport;
struct AvacaRemoteQuicConnection;

struct PendingSend {
  AvacaRemoteQuicConnection* connection = nullptr;
  uint64_t operation = 0;
  uint32_t length = 0;
  uint8_t* bytes = nullptr;
  // Keep the descriptor alive together with the payload until MsQuic emits
  // SEND_COMPLETE. This also makes the bridge independent of whether the
  // provider copies the QUIC_BUFFER array during StreamSend.
  QUIC_BUFFER buffer = {};
};

struct AvacaRemoteQuicConnection {
  AvacaRemoteQuicTransport* transport;
  HQUIC handle = nullptr;
  HQUIC stream = nullptr;
  bool client = false;
  bool started = false;
  bool connected = false;
  bool close_requested = false;
  bool closed = false;
  uint64_t buffered_bytes = 0;
  uint64_t inbound_bytes = 0;
  int32_t shutdown_status = QUIC_STATUS_SUCCESS;
  std::mutex mutex;
  std::unordered_map<void*, PendingSend*> pending_sends;
};

struct AvacaRemoteQuicTransport {
  HMODULE msquic_module = nullptr;
  MsQuicOpenVersionFn open_version = nullptr;
  MsQuicCloseFn close_version = nullptr;
  const QUIC_API_TABLE* api = nullptr;
  HQUIC registration = nullptr;
  HQUIC client_configuration = nullptr;
  HQUIC server_configuration = nullptr;
  HQUIC listener = nullptr;
  AvacaRemoteQuicEventCallback callback = nullptr;
  void* callback_context = nullptr;
  uint8_t pinned_server_certificate_sha256[kChannelBindingLength] = {};
  QUIC_CERTIFICATE_HASH server_certificate_hash = {};
  bool has_server_certificate = false;
  bool closing = false;
  std::mutex mutex;
  std::unordered_map<HQUIC, AvacaRemoteQuicConnection*> connections;
  std::vector<AvacaRemoteQuicConnection*> retired_connections;

  void emit(
      uint64_t object,
      uint32_t event,
      int32_t status = QUIC_STATUS_SUCCESS,
      uint64_t operation = 0,
      const uint8_t* data = nullptr,
      uint32_t length = 0,
      uint8_t flags = 0) {
    if (callback == nullptr) {
      return;
    }
    callback(
        callback_context,
        object,
        event,
        status,
        operation,
        data,
        length,
        flags);
  }

  void emit_owned(
      uint64_t object,
      uint32_t event,
      int32_t status,
      uint64_t operation,
      const uint8_t* data,
      uint32_t length,
      uint8_t flags = 0) {
    if (length == 0) {
      emit(object, event, status, operation, nullptr, 0, flags);
      return;
    }
    auto* copy = static_cast<uint8_t*>(CoTaskMemAlloc(length));
    if (copy == nullptr) {
      emit(object, AVACA_REMOTE_QUIC_EVENT_ERROR, E_OUTOFMEMORY);
      return;
    }
    std::memcpy(copy, data, length);
    if (callback == nullptr) {
      CoTaskMemFree(copy);
      return;
    }
    emit(object, event, status, operation, copy, length, flags);
  }

  void add_connection(AvacaRemoteQuicConnection* connection) {
    std::lock_guard<std::mutex> lock(mutex);
    connections.emplace(connection->handle, connection);
  }

  AvacaRemoteQuicConnection* find_connection(HQUIC handle) {
    std::lock_guard<std::mutex> lock(mutex);
    const auto found = connections.find(handle);
    return found == connections.end() ? nullptr : found->second;
  }

  AvacaRemoteQuicConnection* find_connection_object(uint64_t object) {
    std::lock_guard<std::mutex> lock(mutex);
    for (const auto& entry : connections) {
      if (reinterpret_cast<uint64_t>(entry.second) == object) {
        return entry.second;
      }
    }
    for (auto* connection : retired_connections) {
      if (reinterpret_cast<uint64_t>(connection) == object) {
        return connection;
      }
    }
    return nullptr;
  }

  void remove_connection(HQUIC handle) {
    std::lock_guard<std::mutex> lock(mutex);
    connections.erase(handle);
  }

  void retire_connection(AvacaRemoteQuicConnection* connection) {
    std::lock_guard<std::mutex> lock(mutex);
    connections.erase(connection->handle);
    retired_connections.push_back(connection);
  }

  std::vector<AvacaRemoteQuicConnection*> take_all_connections() {
    std::lock_guard<std::mutex> lock(mutex);
    std::vector<AvacaRemoteQuicConnection*> result;
    result.reserve(connections.size() + retired_connections.size());
    for (const auto& entry : connections) {
      result.push_back(entry.second);
    }
    connections.clear();
    result.insert(
        result.end(), retired_connections.begin(), retired_connections.end());
    retired_connections.clear();
    return result;
  }
};

QUIC_STATUS QUIC_API ListenerCallback(
    HQUIC listener,
    void* context,
    QUIC_LISTENER_EVENT* event);
QUIC_STATUS QUIC_API ConnectionCallback(
    HQUIC connection,
    void* context,
    QUIC_CONNECTION_EVENT* event);
QUIC_STATUS QUIC_API StreamCallback(
    HQUIC stream,
    void* context,
    QUIC_STREAM_EVENT* event);

bool ConstantTimeEquals(
    const uint8_t* left,
    const uint8_t* right,
    size_t length) {
  uint8_t difference = 0;
  for (size_t index = 0; index < length; ++index) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

bool HashSha256(
    const uint8_t* input,
    uint32_t input_length,
    uint8_t output[kChannelBindingLength]) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(
          &algorithm,
          BCRYPT_SHA256_ALGORITHM,
          nullptr,
          0) != 0) {
    return false;
  }
  const auto status = BCryptHash(
      algorithm,
      nullptr,
      0,
      const_cast<PUCHAR>(input),
      input_length,
      output,
      kChannelBindingLength);
  BCryptCloseAlgorithmProvider(algorithm, 0);
  return status == 0;
}

bool IsPinnedCertificate(
    AvacaRemoteQuicConnection* connection,
    QUIC_CERTIFICATE* certificate) {
  if (certificate == nullptr) {
    return false;
  }

  // QUIC_CREDENTIAL_FLAG_USE_PORTABLE_CERTIFICATES makes the Schannel
  // certificate callback expose a QUIC_BUFFER containing the leaf DER.
  const auto* portable = reinterpret_cast<const QUIC_BUFFER*>(certificate);
  if (portable->Buffer == nullptr || portable->Length == 0) {
    return false;
  }
  uint8_t digest[kChannelBindingLength] = {};
  if (!HashSha256(portable->Buffer, portable->Length, digest)) {
    return false;
  }
  return ConstantTimeEquals(
      digest,
      connection->transport->pinned_server_certificate_sha256,
      kChannelBindingLength);
}

HMODULE LoadAdjacentMsQuic() {
  HMODULE bridge_module = nullptr;
  if (!GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(&LoadAdjacentMsQuic),
          &bridge_module)) {
    return nullptr;
  }

  wchar_t module_path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(
      bridge_module,
      module_path,
      static_cast<DWORD>(sizeof(module_path) / sizeof(module_path[0])));
  if (length == 0 ||
      length >= sizeof(module_path) / sizeof(module_path[0])) {
    return nullptr;
  }
  std::wstring path(module_path, length);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return nullptr;
  }
  path.resize(separator + 1);
  path.append(L"msquic.dll");
  return LoadLibraryExW(
      path.c_str(),
      nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
}

void FreePendingSend(PendingSend* pending) {
  if (pending == nullptr) {
    return;
  }
  std::free(pending->bytes);
  std::free(pending);
}

void FreePendingSends(AvacaRemoteQuicConnection* connection) {
  std::vector<PendingSend*> pending;
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    for (const auto& entry : connection->pending_sends) {
      pending.push_back(entry.second);
    }
    connection->pending_sends.clear();
    connection->buffered_bytes = 0;
    connection->inbound_bytes = 0;
  }
  for (auto* item : pending) {
    FreePendingSend(item);
  }
}

void ReleaseInboundBytes(
    AvacaRemoteQuicConnection* connection,
    uint64_t length) {
  if (connection == nullptr || length == 0) {
    return;
  }
  std::lock_guard<std::mutex> lock(connection->mutex);
  if (connection->inbound_bytes >= length) {
    connection->inbound_bytes -= length;
  } else {
    connection->inbound_bytes = 0;
  }
}

void RetireConnectionAfterClose(AvacaRemoteQuicConnection* connection) {
  auto* transport = connection->transport;
  // NativeCallable.listener may deliver the Dart event after this MsQuic
  // callback returns. Keep the wrapper (and its pending-send table) alive
  // until the registration is closed, so a queued Dart write/close can only
  // observe the closed bit instead of dereferencing freed state.
  transport->retire_connection(connection);
}

void ShutdownConnection(AvacaRemoteQuicConnection* connection) {
  if (connection == nullptr || connection->transport == nullptr) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    if (connection->closed || connection->close_requested) {
      return;
    }
    connection->close_requested = true;
  }
  connection->transport->api->ConnectionShutdown(
      connection->handle,
      QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT,
      0);
}

void RejectCertificate(
    AvacaRemoteQuicConnection* connection,
    QUIC_CONNECTION_EVENT* event) {
  const bool accepted = IsPinnedCertificate(
      connection,
      event->PEER_CERTIFICATE_RECEIVED.Certificate);
  connection->transport->api->ConnectionCertificateValidationComplete(
      connection->handle,
      accepted ? TRUE : FALSE,
      accepted ? QUIC_TLS_ALERT_CODE_SUCCESS
               : QUIC_TLS_ALERT_CODE_BAD_CERTIFICATE);
  if (!accepted) {
    connection->transport->emit(
        reinterpret_cast<uint64_t>(connection),
        AVACA_REMOTE_QUIC_EVENT_ERROR,
        QUIC_STATUS_BAD_CERTIFICATE);
  }
}

QUIC_STATUS StartClientStream(AvacaRemoteQuicConnection* connection) {
  HQUIC stream = nullptr;
  auto* transport = connection->transport;
  QUIC_STATUS status = transport->api->StreamOpen(
      connection->handle,
      QUIC_STREAM_OPEN_FLAG_NONE,
      StreamCallback,
      connection,
      &stream);
  if (QUIC_FAILED(status)) {
    return status;
  }
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->stream = stream;
  }
  status = transport->api->StreamStart(
      stream,
      QUIC_STREAM_START_FLAG_IMMEDIATE);
  if (QUIC_FAILED(status)) {
    transport->api->StreamClose(stream);
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->stream = nullptr;
  }
  return status;
}

QUIC_STATUS OnConnected(
    AvacaRemoteQuicConnection* connection,
    QUIC_CONNECTION_EVENT* event) {
  auto* transport = connection->transport;
  uint8_t binding[kChannelBindingLength] = {};
  QUIC_KEYING_MATERIAL_CONFIG config = {};
  config.Label = kExporterLabel;
  config.ContextLength = 0;
  config.Context = nullptr;
  config.OutputLength = kChannelBindingLength;
  const auto status = transport->api->ConnectionExportKeyingMaterial(
      connection->handle,
      &config,
      binding);
  if (QUIC_FAILED(status)) {
    transport->emit(
        reinterpret_cast<uint64_t>(connection),
        AVACA_REMOTE_QUIC_EVENT_ERROR,
        status);
    ShutdownConnection(connection);
    return QUIC_STATUS_SUCCESS;
  }

  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->connected = true;
  }
  transport->emit_owned(
      reinterpret_cast<uint64_t>(connection),
      AVACA_REMOTE_QUIC_EVENT_CONNECTED,
      QUIC_STATUS_SUCCESS,
      0,
      binding,
      kChannelBindingLength);
  (void)event;
  return QUIC_STATUS_SUCCESS;
}

QUIC_STATUS OnPeerStreamStarted(
    AvacaRemoteQuicConnection* connection,
    QUIC_CONNECTION_EVENT* event) {
  auto* stream = event->PEER_STREAM_STARTED.Stream;
  auto* transport = connection->transport;
  transport->api->SetCallbackHandler(stream, StreamCallback, connection);
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    if (connection->stream == nullptr &&
        (event->PEER_STREAM_STARTED.Flags &
         QUIC_STREAM_OPEN_FLAG_UNIDIRECTIONAL) == 0) {
      connection->stream = stream;
      return QUIC_STATUS_SUCCESS;
    }
  }
  transport->api->StreamShutdown(
      stream,
      static_cast<QUIC_STREAM_SHUTDOWN_FLAGS>(
          QUIC_STREAM_SHUTDOWN_FLAG_ABORT |
          QUIC_STREAM_SHUTDOWN_FLAG_IMMEDIATE),
      0);
  return QUIC_STATUS_SUCCESS;
}

QUIC_STATUS QUIC_API StreamCallback(
    HQUIC stream,
    void* context,
    QUIC_STREAM_EVENT* event) {
  auto* connection = static_cast<AvacaRemoteQuicConnection*>(context);
  if (connection == nullptr || connection->transport == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  auto* transport = connection->transport;
  switch (event->Type) {
    case QUIC_STREAM_EVENT_START_COMPLETE:
      if (QUIC_FAILED(event->START_COMPLETE.Status)) {
        transport->emit(
            reinterpret_cast<uint64_t>(connection),
            AVACA_REMOTE_QUIC_EVENT_ERROR,
            event->START_COMPLETE.Status);
        ShutdownConnection(connection);
      }
      break;

    case QUIC_STREAM_EVENT_RECEIVE: {
      const uint64_t total = event->RECEIVE.TotalBufferLength;
      if (total > kMaxReceiveBytes || total > UINT32_MAX) {
        transport->emit(
            reinterpret_cast<uint64_t>(connection),
            AVACA_REMOTE_QUIC_EVENT_ERROR,
            QUIC_STATUS_OUT_OF_MEMORY);
        ShutdownConnection(connection);
        break;
      }
      bool receiveAccepted = false;
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        if (!connection->closed && !connection->close_requested &&
            total <=
                kMaxBufferedBytes -
                    std::min(connection->inbound_bytes, kMaxBufferedBytes)) {
          connection->inbound_bytes += total;
          receiveAccepted = true;
        }
      }
      if (!receiveAccepted) {
        transport->emit(
            reinterpret_cast<uint64_t>(connection),
            AVACA_REMOTE_QUIC_EVENT_ERROR,
            QUIC_STATUS_OUT_OF_MEMORY);
        ShutdownConnection(connection);
        break;
      }
      const auto length = static_cast<uint32_t>(total);
      uint8_t* copy = nullptr;
      if (length > 0) {
        copy = static_cast<uint8_t*>(CoTaskMemAlloc(length));
      }
      bool copied = length == 0 || copy != nullptr;
      uint64_t offset = 0;
      for (uint32_t index = 0; copied && index < event->RECEIVE.BufferCount;
           ++index) {
        const auto& buffer = event->RECEIVE.Buffers[index];
        if (buffer.Length > length - offset) {
          copied = false;
          break;
        }
        if (buffer.Length > 0) {
          std::memcpy(copy + offset, buffer.Buffer, buffer.Length);
          offset += buffer.Length;
        }
      }
      // Returning success below tells MsQuic that all indicated bytes were
      // consumed. Do not call StreamReceiveComplete here as well: doing both
      // would drain the receive window twice and can block later stream data.
      if (!copied || offset != total) {
        if (copy != nullptr) {
          CoTaskMemFree(copy);
        }
        ReleaseInboundBytes(connection, total);
        transport->emit(
            reinterpret_cast<uint64_t>(connection),
            AVACA_REMOTE_QUIC_EVENT_ERROR,
            E_OUTOFMEMORY);
        ShutdownConnection(connection);
        break;
      }
      transport->emit(
          reinterpret_cast<uint64_t>(connection),
          AVACA_REMOTE_QUIC_EVENT_DATA,
          QUIC_STATUS_SUCCESS,
          0,
          copy,
          length,
          (event->RECEIVE.Flags & QUIC_RECEIVE_FLAG_FIN) != 0 ? 1 : 0);
      if (transport->callback == nullptr && copy != nullptr) {
        CoTaskMemFree(copy);
        ReleaseInboundBytes(connection, total);
      }
      break;
    }

    case QUIC_STREAM_EVENT_SEND_COMPLETE: {
      auto* pending = static_cast<PendingSend*>(
          event->SEND_COMPLETE.ClientContext);
      if (pending == nullptr) {
        break;
      }
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        connection->pending_sends.erase(pending);
        if (connection->buffered_bytes >= pending->length) {
          connection->buffered_bytes -= pending->length;
        } else {
          connection->buffered_bytes = 0;
        }
      }
      transport->emit(
          reinterpret_cast<uint64_t>(connection),
          AVACA_REMOTE_QUIC_EVENT_SEND_COMPLETE,
          event->SEND_COMPLETE.Canceled ? QUIC_STATUS_ABORTED
                                        : QUIC_STATUS_SUCCESS,
          pending->operation);
      FreePendingSend(pending);
      break;
    }

    case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
    case QUIC_STREAM_EVENT_PEER_RECEIVE_ABORTED:
      transport->emit(
          reinterpret_cast<uint64_t>(connection),
          AVACA_REMOTE_QUIC_EVENT_ERROR,
          QUIC_STATUS_ABORTED);
      ShutdownConnection(connection);
      break;

    case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE: {
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        if (connection->stream == stream) {
          connection->stream = nullptr;
        }
      }
      transport->api->StreamClose(stream);
      break;
    }

    default:
      break;
  }
  return QUIC_STATUS_SUCCESS;
}

QUIC_STATUS QUIC_API ConnectionCallback(
    HQUIC handle,
    void* context,
    QUIC_CONNECTION_EVENT* event) {
  auto* connection = static_cast<AvacaRemoteQuicConnection*>(context);
  if (connection == nullptr || connection->transport == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  auto* transport = connection->transport;
  switch (event->Type) {
    case QUIC_CONNECTION_EVENT_CONNECTED:
      return OnConnected(connection, event);

    case QUIC_CONNECTION_EVENT_PEER_CERTIFICATE_RECEIVED:
      if (connection->client) {
        RejectCertificate(connection, event);
        return QUIC_STATUS_PENDING;
      }
      return QUIC_STATUS_SUCCESS;

    case QUIC_CONNECTION_EVENT_PEER_STREAM_STARTED:
      return OnPeerStreamStarted(connection, event);

    case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
      connection->shutdown_status =
          event->SHUTDOWN_INITIATED_BY_TRANSPORT.Status;
      break;

    case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE: {
      const auto object = reinterpret_cast<uint64_t>(connection);
      int32_t status = connection->shutdown_status;
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        connection->closed = true;
      }
      transport->emit(object, AVACA_REMOTE_QUIC_EVENT_CLOSED, status);
      transport->api->ConnectionClose(handle);
      RetireConnectionAfterClose(connection);
      return QUIC_STATUS_SUCCESS;
    }

    default:
      break;
  }
  return QUIC_STATUS_SUCCESS;
}

QUIC_STATUS QUIC_API ListenerCallback(
    HQUIC listener,
    void* context,
    QUIC_LISTENER_EVENT* event) {
  auto* transport = static_cast<AvacaRemoteQuicTransport*>(context);
  if (transport == nullptr || transport->api == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  if (event->Type != QUIC_LISTENER_EVENT_NEW_CONNECTION) {
    return QUIC_STATUS_SUCCESS;
  }

  auto* connection = new (std::nothrow) AvacaRemoteQuicConnection();
  if (connection == nullptr) {
    return QUIC_STATUS_OUT_OF_MEMORY;
  }
  connection->transport = transport;
  connection->handle = event->NEW_CONNECTION.Connection;
  connection->started = true;
  connection->client = false;
  transport->add_connection(connection);
  transport->api->SetCallbackHandler(
      connection->handle,
      ConnectionCallback,
      connection);
  const auto status = transport->api->ConnectionSetConfiguration(
      connection->handle,
      transport->server_configuration);
  if (QUIC_FAILED(status)) {
    transport->remove_connection(connection->handle);
    FreePendingSends(connection);
    delete connection;
    return status;
  }
  (void)listener;
  return QUIC_STATUS_SUCCESS;
}

bool BuildSettings(QUIC_SETTINGS* settings) {
  if (settings == nullptr) {
    return false;
  }
  *settings = {};
  settings->IsSet.IdleTimeoutMs = TRUE;
  settings->IdleTimeoutMs = 60'000;
  settings->IsSet.PeerBidiStreamCount = TRUE;
  settings->PeerBidiStreamCount = 1;
  return true;
}

QUIC_STATUS OpenConfiguration(
    AvacaRemoteQuicTransport* transport,
    bool server,
    HQUIC* configuration) {
  QUIC_BUFFER alpn = {
      static_cast<uint32_t>(sizeof(kAlpn) - 1),
      const_cast<uint8_t*>(reinterpret_cast<const uint8_t*>(kAlpn))};
  QUIC_SETTINGS settings = {};
  BuildSettings(&settings);
  auto status = transport->api->ConfigurationOpen(
      transport->registration,
      &alpn,
      1,
      &settings,
      sizeof(settings),
      nullptr,
      configuration);
  if (QUIC_FAILED(status)) {
    return status;
  }

  QUIC_CREDENTIAL_CONFIG credential = {};
  if (server) {
    credential.Type = QUIC_CREDENTIAL_TYPE_CERTIFICATE_HASH;
    credential.CertificateHash = &transport->server_certificate_hash;
  } else {
    credential.Type = QUIC_CREDENTIAL_TYPE_NONE;
    credential.Flags = static_cast<QUIC_CREDENTIAL_FLAGS>(
        QUIC_CREDENTIAL_FLAG_CLIENT |
        QUIC_CREDENTIAL_FLAG_INDICATE_CERTIFICATE_RECEIVED |
        QUIC_CREDENTIAL_FLAG_DEFER_CERTIFICATE_VALIDATION |
        QUIC_CREDENTIAL_FLAG_USE_PORTABLE_CERTIFICATES);
  }
  status = transport->api->ConfigurationLoadCredential(
      *configuration,
      &credential);
  if (QUIC_FAILED(status)) {
    transport->api->ConfigurationClose(*configuration);
    *configuration = nullptr;
  }
  return status;
}

int32_t CloseTransport(AvacaRemoteQuicTransport* transport) {
  if (transport == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  {
    std::lock_guard<std::mutex> lock(transport->mutex);
    if (transport->closing) {
      return QUIC_STATUS_SUCCESS;
    }
    transport->closing = true;
  }

  if (transport->listener != nullptr) {
    const auto listener = transport->listener;
    transport->listener = nullptr;
    transport->api->ListenerClose(listener);
  }
  if (transport->registration != nullptr) {
    transport->api->RegistrationShutdown(
        transport->registration,
        QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT,
        0);
  }
  if (transport->server_configuration != nullptr) {
    transport->api->ConfigurationClose(transport->server_configuration);
    transport->server_configuration = nullptr;
  }
  if (transport->client_configuration != nullptr) {
    transport->api->ConfigurationClose(transport->client_configuration);
    transport->client_configuration = nullptr;
  }
  if (transport->registration != nullptr) {
    transport->api->RegistrationClose(transport->registration);
    transport->registration = nullptr;
  }
  for (auto* connection : transport->take_all_connections()) {
    FreePendingSends(connection);
    delete connection;
  }
  if (transport->close_version != nullptr && transport->api != nullptr) {
    transport->close_version(transport->api);
    transport->api = nullptr;
  }
  if (transport->msquic_module != nullptr) {
    FreeLibrary(transport->msquic_module);
    transport->msquic_module = nullptr;
  }
  delete transport;
  return QUIC_STATUS_SUCCESS;
}

}  // namespace

extern "C" {

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_create(
    const uint8_t* pinned_server_certificate_sha256,
    uint32_t pinned_server_certificate_sha256_length,
    const uint8_t* server_certificate_sha1,
    uint32_t server_certificate_sha1_length,
    AvacaRemoteQuicEventCallback callback,
    void* context,
    uint64_t* transport_handle) {
  if (pinned_server_certificate_sha256 == nullptr ||
      pinned_server_certificate_sha256_length != kChannelBindingLength ||
      (server_certificate_sha1_length != 0 &&
       (server_certificate_sha1 == nullptr || server_certificate_sha1_length != 20)) ||
      callback == nullptr || transport_handle == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }

  auto* transport = new (std::nothrow) AvacaRemoteQuicTransport();
  if (transport == nullptr) {
    return QUIC_STATUS_OUT_OF_MEMORY;
  }
  std::memcpy(
      transport->pinned_server_certificate_sha256,
      pinned_server_certificate_sha256,
      kChannelBindingLength);
  if (server_certificate_sha1_length == 20) {
    std::memcpy(
        transport->server_certificate_hash.ShaHash,
        server_certificate_sha1,
        20);
    transport->has_server_certificate = true;
  }
  transport->callback = callback;
  transport->callback_context = context;
  transport->msquic_module = LoadAdjacentMsQuic();
  if (transport->msquic_module == nullptr) {
    delete transport;
    return QUIC_STATUS_NOT_FOUND;
  }
  transport->open_version = reinterpret_cast<MsQuicOpenVersionFn>(
      GetProcAddress(transport->msquic_module, "MsQuicOpenVersion"));
  transport->close_version = reinterpret_cast<MsQuicCloseFn>(
      GetProcAddress(transport->msquic_module, "MsQuicClose"));
  if (transport->open_version == nullptr || transport->close_version == nullptr) {
    FreeLibrary(transport->msquic_module);
    delete transport;
    return QUIC_STATUS_NOT_FOUND;
  }
  const void* raw_api = nullptr;
  auto status = transport->open_version(2, &raw_api);
  if (QUIC_FAILED(status) || raw_api == nullptr) {
    FreeLibrary(transport->msquic_module);
    delete transport;
    return status;
  }
  transport->api = static_cast<const QUIC_API_TABLE*>(raw_api);
  if (transport->api->ConnectionExportKeyingMaterial == nullptr) {
    transport->close_version(transport->api);
    FreeLibrary(transport->msquic_module);
    delete transport;
    return QUIC_STATUS_NOT_SUPPORTED;
  }

  QUIC_REGISTRATION_CONFIG registration_config = {};
  registration_config.AppName = "AVACA Remote";
  registration_config.ExecutionProfile = QUIC_EXECUTION_PROFILE_LOW_LATENCY;
  status = transport->api->RegistrationOpen(
      &registration_config,
      &transport->registration);
  if (QUIC_FAILED(status)) {
    transport->close_version(transport->api);
    FreeLibrary(transport->msquic_module);
    delete transport;
    return status;
  }
  status = OpenConfiguration(
      transport,
      false,
      &transport->client_configuration);
  if (QUIC_FAILED(status)) {
    transport->api->RegistrationClose(transport->registration);
    transport->close_version(transport->api);
    FreeLibrary(transport->msquic_module);
    delete transport;
    return status;
  }
  if (transport->has_server_certificate) {
    status = OpenConfiguration(
        transport,
        true,
        &transport->server_configuration);
    if (QUIC_FAILED(status)) {
      transport->api->ConfigurationClose(transport->client_configuration);
      transport->api->RegistrationClose(transport->registration);
      transport->close_version(transport->api);
      FreeLibrary(transport->msquic_module);
      delete transport;
      return status;
    }
  }
  *transport_handle = reinterpret_cast<uint64_t>(transport);
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_listen(
    uint64_t transport_handle,
    uint16_t port,
    uint64_t* listener_handle) {
  auto* transport = reinterpret_cast<AvacaRemoteQuicTransport*>(transport_handle);
  if (transport == nullptr || listener_handle == nullptr || port == 0 ||
      !transport->has_server_certificate ||
      transport->server_configuration == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  if (transport->listener != nullptr) {
    return QUIC_STATUS_INVALID_STATE;
  }
  HQUIC listener = nullptr;
  auto status = transport->api->ListenerOpen(
      transport->registration,
      ListenerCallback,
      transport,
      &listener);
  if (QUIC_FAILED(status)) {
    return status;
  }
  QUIC_ADDR address = {};
  QuicAddrSetFamily(&address, QUIC_ADDRESS_FAMILY_UNSPEC);
  QuicAddrSetPort(&address, port);
  QUIC_BUFFER alpn = {
      static_cast<uint32_t>(sizeof(kAlpn) - 1),
      const_cast<uint8_t*>(reinterpret_cast<const uint8_t*>(kAlpn))};
  status = transport->api->ListenerStart(listener, &alpn, 1, &address);
  if (QUIC_FAILED(status)) {
    transport->api->ListenerClose(listener);
    return status;
  }
  transport->listener = listener;
  *listener_handle = reinterpret_cast<uint64_t>(listener);
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_connect(
    uint64_t transport_handle,
    const char* host,
    uint16_t port,
    uint64_t* connection_handle) {
  auto* transport = reinterpret_cast<AvacaRemoteQuicTransport*>(transport_handle);
  if (transport == nullptr || host == nullptr || host[0] == '\0' ||
      port == 0 || connection_handle == nullptr || transport->closing) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  auto* connection = new (std::nothrow) AvacaRemoteQuicConnection();
  if (connection == nullptr) {
    return QUIC_STATUS_OUT_OF_MEMORY;
  }
  connection->transport = transport;
  connection->client = true;
  HQUIC handle = nullptr;
  auto status = transport->api->ConnectionOpen(
      transport->registration,
      ConnectionCallback,
      connection,
      &handle);
  if (QUIC_FAILED(status)) {
    delete connection;
    return status;
  }
  connection->handle = handle;
  connection->started = true;
  transport->add_connection(connection);
  // MsQuic permits the client stream to be opened and started before the
  // connection start. This makes the stream available as soon as the
  // connection reaches CONNECTED and matches the official API sequence.
  status = StartClientStream(connection);
  if (QUIC_FAILED(status)) {
    transport->api->ConnectionClose(handle);
    transport->remove_connection(handle);
    FreePendingSends(connection);
    delete connection;
    return status;
  }
  // The public handle is the bridge-owned wrapper, not the opaque MsQuic
  // HQUIC. This keeps later FFI calls tied to the wrapper that owns the
  // pending-send and stream state.
  *connection_handle = reinterpret_cast<uint64_t>(connection);
  status = transport->api->ConnectionStart(
      handle,
      transport->client_configuration,
      QUIC_ADDRESS_FAMILY_UNSPEC,
      host,
      port);
  if (QUIC_FAILED(status)) {
    transport->api->ConnectionClose(handle);
    transport->remove_connection(handle);
    FreePendingSends(connection);
    delete connection;
    *connection_handle = 0;
    return status;
  }
  // MsQuic reports an asynchronously started connection as
  // QUIC_STATUS_PENDING. The Dart-facing C ABI uses zero for a successfully
  // started operation, so do not expose the platform-specific success HRESULT
  // as a connection-start failure.
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_send(
    uint64_t connection_handle,
    const uint8_t* data,
    uint32_t length,
    uint64_t operation) {
  auto* connection = reinterpret_cast<AvacaRemoteQuicConnection*>(connection_handle);
  if (connection == nullptr || data == nullptr || length == 0 || operation == 0 ||
      connection->transport == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  HQUIC stream = nullptr;
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    if (connection->closed || !connection->connected || connection->stream == nullptr ||
        length > kMaxBufferedBytes - std::min(connection->buffered_bytes, kMaxBufferedBytes)) {
      return connection->closed ? QUIC_STATUS_INVALID_STATE : QUIC_STATUS_OUT_OF_MEMORY;
    }
    stream = connection->stream;
  }
  auto* pending = static_cast<PendingSend*>(std::malloc(sizeof(PendingSend)));
  if (pending == nullptr) {
    return QUIC_STATUS_OUT_OF_MEMORY;
  }
  *pending = {};
  pending->connection = connection;
  pending->operation = operation;
  pending->length = length;
  pending->bytes = static_cast<uint8_t*>(std::malloc(length));
  if (pending->bytes == nullptr) {
    FreePendingSend(pending);
    return QUIC_STATUS_OUT_OF_MEMORY;
  }
  std::memcpy(pending->bytes, data, length);
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    if (connection->closed || connection->stream != stream ||
        connection->buffered_bytes > kMaxBufferedBytes - length) {
      FreePendingSend(pending);
      return QUIC_STATUS_INVALID_STATE;
    }
    connection->pending_sends.emplace(pending, pending);
    connection->buffered_bytes += length;
  }
  pending->buffer = {length, pending->bytes};
  const auto status = connection->transport->api->StreamSend(
      stream,
      &pending->buffer,
      1,
      QUIC_SEND_FLAG_NONE,
      pending);
  if (QUIC_FAILED(status)) {
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->pending_sends.erase(pending);
    if (connection->buffered_bytes >= length) {
      connection->buffered_bytes -= length;
    }
    FreePendingSend(pending);
    return status;
  }
  // StreamSend may return QUIC_STATUS_PENDING for a successfully queued
  // asynchronous send. Keep the Dart-facing C ABI's zero-success contract
  // stable while the completion callback reports the final operation result.
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_close_connection(uint64_t connection_handle) {
  auto* connection = reinterpret_cast<AvacaRemoteQuicConnection*>(connection_handle);
  if (connection == nullptr || connection->transport == nullptr) {
    return QUIC_STATUS_SUCCESS;
  }
  ShutdownConnection(connection);
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_close_listener(
    uint64_t transport_handle,
    uint64_t listener_handle) {
  auto* transport = reinterpret_cast<AvacaRemoteQuicTransport*>(transport_handle);
  if (transport == nullptr || listener_handle == 0) {
    return QUIC_STATUS_SUCCESS;
  }
  if (transport->listener == reinterpret_cast<HQUIC>(listener_handle)) {
    const auto listener = transport->listener;
    transport->listener = nullptr;
    transport->api->ListenerClose(listener);
  }
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_close(uint64_t transport_handle) {
  return CloseTransport(
      reinterpret_cast<AvacaRemoteQuicTransport*>(transport_handle));
}

AVACA_REMOTE_QUIC_API void AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_ack_receive(
    uint64_t transport_handle,
    uint64_t connection_object,
    uint32_t length) {
  if (transport_handle == 0 || connection_object == 0 || length == 0) {
    return;
  }
  auto* transport = reinterpret_cast<AvacaRemoteQuicTransport*>(transport_handle);
  auto* connection = transport->find_connection_object(connection_object);
  // MsQuic already consumed the receive indication when StreamCallback
  // returned success. This acknowledgement only releases the bridge's
  // application-buffer quota.
  ReleaseInboundBytes(connection, length);
}

AVACA_REMOTE_QUIC_API void AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_free_buffer(const uint8_t* data) {
  if (data != nullptr) {
    CoTaskMemFree(const_cast<uint8_t*>(data));
  }
}

}  // extern "C"

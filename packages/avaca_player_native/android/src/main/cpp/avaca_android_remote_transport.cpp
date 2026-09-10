#ifndef QUIC_API_ENABLE_PREVIEW_FEATURES
#define QUIC_API_ENABLE_PREVIEW_FEATURES
#endif

#include <msquic.h>
#include <android/log.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

constexpr uint32_t kChannelBindingLength = 32;
constexpr uint64_t kMaxBufferedBytes = 16ull * 1024ull * 1024ull;
constexpr uint32_t kMaxReceiveBytes = 16u * 1024u * 1024u;
constexpr char kAlpn[] = "avaca-remote/2";
constexpr char kExporterLabel[] = "EXPORTER-AVACA-REMOTE-V2";

enum : uint32_t {
  kEventConnected = 1,
  kEventData = 2,
  kEventSendComplete = 3,
  kEventClosed = 4,
  kEventError = 5,
};

using EventCallback = void (*)(
    void* context,
    uint64_t object,
    uint32_t event,
    int32_t status,
    uint64_t operation,
    const uint8_t* data,
    uint32_t length,
    uint8_t flags);

void LogQuicStatus(const char* stage, QUIC_STATUS status) {
  __android_log_print(
      ANDROID_LOG_ERROR, "AVACA_QUIC", "%s status=0x%08x", stage,
      static_cast<uint32_t>(status));
}

void LogQuicEvent(const char* stage, uint32_t event_type) {
  __android_log_print(
      ANDROID_LOG_INFO, "AVACA_QUIC", "%s event=%u", stage, event_type);
}

// Keep the Android client self-contained.  Linking a second OpenSSL ABI next
// to MsQuic's bundled quictls is not supported by the player package.
struct Sha256 {
  std::array<uint32_t, 8> state = {
      0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
      0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};
  std::array<uint8_t, 64> block{};
  uint64_t bit_length = 0;
  size_t block_length = 0;
};

constexpr std::array<uint32_t, 64> kSha256Constants = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

uint32_t RotateRight(uint32_t value, uint32_t bits) {
  return (value >> bits) | (value << (32u - bits));
}

void Sha256Block(Sha256* hash, const uint8_t* bytes) {
  std::array<uint32_t, 64> words{};
  for (size_t index = 0; index < 16; ++index) {
    words[index] = (static_cast<uint32_t>(bytes[index * 4]) << 24) |
                   (static_cast<uint32_t>(bytes[index * 4 + 1]) << 16) |
                   (static_cast<uint32_t>(bytes[index * 4 + 2]) << 8) |
                   static_cast<uint32_t>(bytes[index * 4 + 3]);
  }
  for (size_t index = 16; index < words.size(); ++index) {
    const auto s0 = RotateRight(words[index - 15], 7) ^
                    RotateRight(words[index - 15], 18) ^
                    (words[index - 15] >> 3);
    const auto s1 = RotateRight(words[index - 2], 17) ^
                    RotateRight(words[index - 2], 19) ^
                    (words[index - 2] >> 10);
    words[index] = words[index - 16] + s0 + words[index - 7] + s1;
  }
  auto a = hash->state[0];
  auto b = hash->state[1];
  auto c = hash->state[2];
  auto d = hash->state[3];
  auto e = hash->state[4];
  auto f = hash->state[5];
  auto g = hash->state[6];
  auto h = hash->state[7];
  for (size_t index = 0; index < words.size(); ++index) {
    const auto sum1 = RotateRight(e, 6) ^ RotateRight(e, 11) ^
                      RotateRight(e, 25);
    const auto choose = (e & f) ^ ((~e) & g);
    const auto temp1 = h + sum1 + choose + kSha256Constants[index] +
                       words[index];
    const auto sum0 = RotateRight(a, 2) ^ RotateRight(a, 13) ^
                      RotateRight(a, 22);
    const auto majority = (a & b) ^ (a & c) ^ (b & c);
    const auto temp2 = sum0 + majority;
    h = g;
    g = f;
    f = e;
    e = d + temp1;
    d = c;
    c = b;
    b = a;
    a = temp1 + temp2;
  }
  hash->state[0] += a;
  hash->state[1] += b;
  hash->state[2] += c;
  hash->state[3] += d;
  hash->state[4] += e;
  hash->state[5] += f;
  hash->state[6] += g;
  hash->state[7] += h;
}

void Sha256Update(Sha256* hash, const uint8_t* bytes, size_t length) {
  if (hash == nullptr || (length != 0 && bytes == nullptr)) return;
  hash->bit_length += static_cast<uint64_t>(length) * 8;
  while (length != 0) {
    const auto count = std::min(length, hash->block.size() - hash->block_length);
    std::memcpy(hash->block.data() + hash->block_length, bytes, count);
    hash->block_length += count;
    bytes += count;
    length -= count;
    if (hash->block_length == hash->block.size()) {
      Sha256Block(hash, hash->block.data());
      hash->block_length = 0;
    }
  }
}

std::array<uint8_t, 32> Sha256Finish(Sha256* hash) {
  const auto original_bits = hash->bit_length;
  hash->block[hash->block_length++] = 0x80;
  if (hash->block_length > 56) {
    while (hash->block_length < 64) hash->block[hash->block_length++] = 0;
    Sha256Block(hash, hash->block.data());
    hash->block_length = 0;
  }
  while (hash->block_length < 56) hash->block[hash->block_length++] = 0;
  for (int index = 7; index >= 0; --index) {
    hash->block[hash->block_length++] =
        static_cast<uint8_t>((original_bits >> (index * 8)) & 0xffu);
  }
  Sha256Block(hash, hash->block.data());
  std::array<uint8_t, 32> output{};
  for (size_t index = 0; index < hash->state.size(); ++index) {
    output[index * 4] = static_cast<uint8_t>(hash->state[index] >> 24);
    output[index * 4 + 1] = static_cast<uint8_t>(hash->state[index] >> 16);
    output[index * 4 + 2] = static_cast<uint8_t>(hash->state[index] >> 8);
    output[index * 4 + 3] = static_cast<uint8_t>(hash->state[index]);
  }
  return output;
}

std::vector<uint8_t> Sha256Bytes(const uint8_t* bytes, size_t length) {
  Sha256 hash;
  Sha256Update(&hash, bytes, length);
  const auto digest = Sha256Finish(&hash);
  return std::vector<uint8_t>(digest.begin(), digest.end());
}

bool ConstantTimeEquals(const std::vector<uint8_t>& left,
                        const uint8_t* right,
                        size_t right_length) {
  if (left.size() != right_length || right == nullptr) return false;
  uint8_t difference = 0;
  for (size_t index = 0; index < left.size(); ++index) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

void Wipe(std::vector<uint8_t>* bytes) {
  if (bytes == nullptr) return;
  std::fill(bytes->begin(), bytes->end(), 0);
  bytes->clear();
}

struct AndroidRemoteTransport;
struct AndroidRemoteConnection;

struct AndroidPendingSend {
  uint64_t operation = 0;
  uint32_t length = 0;
  std::vector<uint8_t> bytes;
  QUIC_BUFFER buffer{};
};

struct AndroidRemoteConnection {
  AndroidRemoteTransport* transport = nullptr;
  HQUIC handle = nullptr;
  HQUIC stream = nullptr;
  bool connected = false;
  bool close_requested = false;
  bool closed = false;
  uint64_t buffered_bytes = 0;
  uint64_t inbound_bytes = 0;
  int32_t shutdown_status = QUIC_STATUS_SUCCESS;
  std::mutex mutex;
  std::unordered_set<AndroidPendingSend*> pending_sends;
};

struct AndroidRemoteTransport {
  const QUIC_API_TABLE* api = nullptr;
  HQUIC registration = nullptr;
  HQUIC client_configuration = nullptr;
  EventCallback callback = nullptr;
  void* callback_context = nullptr;
  std::array<uint8_t, kChannelBindingLength> pinned_certificate{};
  bool closing = false;
  std::mutex mutex;
  std::unordered_map<HQUIC, AndroidRemoteConnection*> connections;
  std::vector<AndroidRemoteConnection*> retired_connections;

  void emit(uint64_t object,
            uint32_t event,
            int32_t status = QUIC_STATUS_SUCCESS,
            uint64_t operation = 0,
            const uint8_t* data = nullptr,
            uint32_t length = 0,
            uint8_t flags = 0) {
    if (callback != nullptr) {
      callback(callback_context, object, event, status, operation, data, length,
               flags);
    }
  }

  void emit_owned(uint64_t object,
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
    auto* copy = static_cast<uint8_t*>(std::malloc(length));
    if (copy == nullptr) {
      emit(object, kEventError, QUIC_STATUS_OUT_OF_MEMORY);
      return;
    }
    std::memcpy(copy, data, length);
    if (callback == nullptr) {
      std::free(copy);
      return;
    }
    emit(object, event, status, operation, copy, length, flags);
  }

  void add_connection(AndroidRemoteConnection* connection) {
    std::lock_guard<std::mutex> lock(mutex);
    connections.emplace(connection->handle, connection);
  }

  void remove_connection(HQUIC handle) {
    std::lock_guard<std::mutex> lock(mutex);
    connections.erase(handle);
  }

  void retire_connection(AndroidRemoteConnection* connection) {
    std::lock_guard<std::mutex> lock(mutex);
    connections.erase(connection->handle);
    retired_connections.push_back(connection);
  }

  std::vector<AndroidRemoteConnection*> take_all_connections() {
    std::lock_guard<std::mutex> lock(mutex);
    std::vector<AndroidRemoteConnection*> result;
    result.reserve(connections.size() + retired_connections.size());
    for (const auto& entry : connections) result.push_back(entry.second);
    connections.clear();
    result.insert(result.end(), retired_connections.begin(),
                  retired_connections.end());
    retired_connections.clear();
    return result;
  }
};

QUIC_STATUS QUIC_API AndroidConnectionCallback(HQUIC connection,
                                                void* context,
                                                QUIC_CONNECTION_EVENT* event);
QUIC_STATUS QUIC_API AndroidStreamCallback(HQUIC stream,
                                            void* context,
                                            QUIC_STREAM_EVENT* event);

void FreePendingSend(AndroidPendingSend* pending) {
  if (pending == nullptr) return;
  Wipe(&pending->bytes);
  delete pending;
}

void FreePendingSends(AndroidRemoteConnection* connection) {
  if (connection == nullptr) return;
  std::vector<AndroidPendingSend*> pending;
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    pending.insert(pending.end(), connection->pending_sends.begin(),
                   connection->pending_sends.end());
    connection->pending_sends.clear();
    connection->buffered_bytes = 0;
    connection->inbound_bytes = 0;
  }
  for (auto* item : pending) FreePendingSend(item);
}

void ReleaseInboundBytes(AndroidRemoteConnection* connection, uint64_t length) {
  if (connection == nullptr || length == 0) return;
  std::lock_guard<std::mutex> lock(connection->mutex);
  connection->inbound_bytes = connection->inbound_bytes >= length
                                  ? connection->inbound_bytes - length
                                  : 0;
}

void ShutdownConnection(AndroidRemoteConnection* connection) {
  if (connection == nullptr || connection->transport == nullptr) return;
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    if (connection->closed || connection->close_requested) return;
    connection->close_requested = true;
  }
  connection->transport->api->ConnectionShutdown(
      connection->handle, QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT, 0);
}

bool IsPinnedCertificate(AndroidRemoteConnection* connection,
                         QUIC_CERTIFICATE* certificate) {
  if (connection == nullptr || certificate == nullptr) return false;
  const auto* portable = reinterpret_cast<const QUIC_BUFFER*>(certificate);
  if (portable->Buffer == nullptr || portable->Length == 0) return false;
  const auto digest = Sha256Bytes(portable->Buffer, portable->Length);
  return ConstantTimeEquals(digest,
                            connection->transport->pinned_certificate.data(),
                            connection->transport->pinned_certificate.size());
}

void ValidatePeerCertificate(AndroidRemoteConnection* connection,
                             QUIC_CONNECTION_EVENT* event) {
  const bool accepted = IsPinnedCertificate(
      connection, event->PEER_CERTIFICATE_RECEIVED.Certificate);
  const auto* portable = reinterpret_cast<const QUIC_BUFFER*>(
      event->PEER_CERTIFICATE_RECEIVED.Certificate);
  __android_log_print(
      ANDROID_LOG_INFO, "AVACA_QUIC", "peer certificate bytes=%u accepted=%d",
      portable == nullptr ? 0u : portable->Length, accepted ? 1 : 0);
  connection->transport->api->ConnectionCertificateValidationComplete(
      connection->handle, accepted,
      accepted ? QUIC_TLS_ALERT_CODE_SUCCESS
               : QUIC_TLS_ALERT_CODE_BAD_CERTIFICATE);
  if (!accepted) {
    LogQuicStatus("peer certificate rejected", QUIC_STATUS_BAD_CERTIFICATE);
    connection->transport->emit(reinterpret_cast<uint64_t>(connection),
                                kEventError, QUIC_STATUS_BAD_CERTIFICATE);
  }
}

QUIC_STATUS StartClientStream(AndroidRemoteConnection* connection) {
  HQUIC stream = nullptr;
  auto* transport = connection->transport;
  auto status = transport->api->StreamOpen(connection->handle,
                                           QUIC_STREAM_OPEN_FLAG_NONE,
                                           AndroidStreamCallback, connection,
                                           &stream);
  if (QUIC_FAILED(status)) return status;
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->stream = stream;
  }
  status = transport->api->StreamStart(stream,
                                       QUIC_STREAM_START_FLAG_IMMEDIATE);
  if (QUIC_FAILED(status)) {
    transport->api->StreamClose(stream);
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->stream = nullptr;
  }
  return status;
}

QUIC_STATUS OnConnected(AndroidRemoteConnection* connection) {
  std::array<uint8_t, kChannelBindingLength> binding{};
  QUIC_KEYING_MATERIAL_CONFIG config{};
  config.Label = kExporterLabel;
  config.ContextLength = 0;
  config.Context = nullptr;
  config.OutputLength = kChannelBindingLength;
  const auto status = connection->transport->api->ConnectionExportKeyingMaterial(
      connection->handle, &config, binding.data());
  if (QUIC_FAILED(status)) {
    LogQuicStatus("export keying material failed", status);
    connection->transport->emit(reinterpret_cast<uint64_t>(connection),
                                kEventError, status);
    ShutdownConnection(connection);
    return QUIC_STATUS_SUCCESS;
  }
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->connected = true;
  }
  connection->transport->emit_owned(reinterpret_cast<uint64_t>(connection),
                                    kEventConnected, QUIC_STATUS_SUCCESS, 0,
                                    binding.data(), binding.size());
  return QUIC_STATUS_SUCCESS;
}

QUIC_STATUS QUIC_API AndroidStreamCallback(HQUIC stream,
                                            void* context,
                                            QUIC_STREAM_EVENT* event) {
  auto* connection = static_cast<AndroidRemoteConnection*>(context);
  if (connection == nullptr || connection->transport == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  auto* transport = connection->transport;
  __android_log_print(ANDROID_LOG_INFO, "AVACA_QUIC",
                      "stream callback event=%u", event->Type);
  switch (event->Type) {
    case QUIC_STREAM_EVENT_START_COMPLETE:
      if (QUIC_FAILED(event->START_COMPLETE.Status)) {
        LogQuicStatus("stream start failed", event->START_COMPLETE.Status);
        transport->emit(reinterpret_cast<uint64_t>(connection), kEventError,
                        event->START_COMPLETE.Status);
        ShutdownConnection(connection);
      }
      break;

    case QUIC_STREAM_EVENT_RECEIVE: {
      const uint64_t total = event->RECEIVE.TotalBufferLength;
      __android_log_print(ANDROID_LOG_INFO, "AVACA_QUIC",
                          "stream receive bytes=%llu flags=0x%x",
                          static_cast<unsigned long long>(total),
                          event->RECEIVE.Flags);
      if (total > kMaxReceiveBytes || total > UINT32_MAX) {
        transport->emit(reinterpret_cast<uint64_t>(connection), kEventError,
                        QUIC_STATUS_OUT_OF_MEMORY);
        ShutdownConnection(connection);
        break;
      }
      bool receive_accepted = false;
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        if (!connection->closed && !connection->close_requested &&
            total <= kMaxBufferedBytes -
                         std::min(connection->inbound_bytes, kMaxBufferedBytes)) {
          connection->inbound_bytes += total;
          receive_accepted = true;
        }
      }
      if (!receive_accepted) {
        transport->emit(reinterpret_cast<uint64_t>(connection), kEventError,
                        QUIC_STATUS_OUT_OF_MEMORY);
        ShutdownConnection(connection);
        break;
      }
      const auto length = static_cast<uint32_t>(total);
      auto* copy = length == 0
                       ? nullptr
                       : static_cast<uint8_t*>(std::malloc(length));
      bool copied = length == 0 || copy != nullptr;
      uint64_t offset = 0;
      for (uint32_t index = 0;
           copied && index < event->RECEIVE.BufferCount; ++index) {
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
      if (!copied || offset != total) {
        if (copy != nullptr) std::free(copy);
        ReleaseInboundBytes(connection, total);
        transport->emit(reinterpret_cast<uint64_t>(connection), kEventError,
                        QUIC_STATUS_OUT_OF_MEMORY);
        ShutdownConnection(connection);
        break;
      }
      transport->emit(reinterpret_cast<uint64_t>(connection), kEventData,
                      QUIC_STATUS_SUCCESS, 0, copy, length,
                      (event->RECEIVE.Flags & QUIC_RECEIVE_FLAG_FIN) != 0 ? 1
                                                                         : 0);
      if (transport->callback == nullptr && copy != nullptr) {
        std::free(copy);
        ReleaseInboundBytes(connection, total);
      }
      break;
    }

    case QUIC_STREAM_EVENT_SEND_COMPLETE: {
      auto* pending = static_cast<AndroidPendingSend*>(
          event->SEND_COMPLETE.ClientContext);
      if (pending == nullptr) break;
      __android_log_print(ANDROID_LOG_INFO, "AVACA_QUIC",
                          "stream send complete op=%llu canceled=%d",
                          static_cast<unsigned long long>(pending->operation),
                          event->SEND_COMPLETE.Canceled ? 1 : 0);
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        connection->pending_sends.erase(pending);
        connection->buffered_bytes =
            connection->buffered_bytes >= pending->length
                ? connection->buffered_bytes - pending->length
                : 0;
      }
      transport->emit(reinterpret_cast<uint64_t>(connection),
                      kEventSendComplete,
                      event->SEND_COMPLETE.Canceled ? QUIC_STATUS_ABORTED
                                                    : QUIC_STATUS_SUCCESS,
                      pending->operation);
      FreePendingSend(pending);
      break;
    }

    case QUIC_STREAM_EVENT_PEER_SEND_ABORTED:
    case QUIC_STREAM_EVENT_PEER_RECEIVE_ABORTED:
      transport->emit(reinterpret_cast<uint64_t>(connection), kEventError,
                      QUIC_STATUS_ABORTED);
      ShutdownConnection(connection);
      break;

    case QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE: {
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        if (connection->stream == stream) connection->stream = nullptr;
      }
      transport->api->StreamClose(stream);
      break;
    }

    default:
      break;
  }
  return QUIC_STATUS_SUCCESS;
}

QUIC_STATUS QUIC_API AndroidConnectionCallback(HQUIC handle,
                                                void* context,
                                                QUIC_CONNECTION_EVENT* event) {
  auto* connection = static_cast<AndroidRemoteConnection*>(context);
  if (connection == nullptr || connection->transport == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  auto* transport = connection->transport;
  LogQuicEvent("connection callback", event->Type);
  switch (event->Type) {
    case QUIC_CONNECTION_EVENT_CONNECTED:
      return OnConnected(connection);

    case QUIC_CONNECTION_EVENT_PEER_CERTIFICATE_RECEIVED:
      ValidatePeerCertificate(connection, event);
      return QUIC_STATUS_PENDING;

    case QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT:
      connection->shutdown_status =
          event->SHUTDOWN_INITIATED_BY_TRANSPORT.Status;
      LogQuicStatus("transport shutdown", connection->shutdown_status);
      break;

    case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE: {
      const auto object = reinterpret_cast<uint64_t>(connection);
      int32_t status = connection->shutdown_status;
      LogQuicStatus("connection shutdown complete", status);
      {
        std::lock_guard<std::mutex> lock(connection->mutex);
        connection->closed = true;
      }
      transport->emit(object, kEventClosed, status);
      transport->api->ConnectionClose(handle);
      transport->retire_connection(connection);
      break;
    }

    default:
      break;
  }
  return QUIC_STATUS_SUCCESS;
}

bool BuildSettings(QUIC_SETTINGS* settings) {
  if (settings == nullptr) return false;
  *settings = {};
  settings->IsSet.IdleTimeoutMs = true;
  settings->IdleTimeoutMs = 60'000;
  settings->IsSet.PeerBidiStreamCount = true;
  settings->PeerBidiStreamCount = 1;
  return true;
}

QUIC_STATUS OpenClientConfiguration(AndroidRemoteTransport* transport) {
  QUIC_BUFFER alpn{static_cast<uint32_t>(sizeof(kAlpn) - 1),
                   const_cast<uint8_t*>(
                       reinterpret_cast<const uint8_t*>(kAlpn))};
  QUIC_SETTINGS settings{};
  BuildSettings(&settings);
  auto status = transport->api->ConfigurationOpen(
      transport->registration, &alpn, 1, &settings, sizeof(settings), nullptr,
      &transport->client_configuration);
  if (QUIC_FAILED(status)) return status;

  QUIC_CREDENTIAL_CONFIG credential{};
  credential.Type = QUIC_CREDENTIAL_TYPE_NONE;
  credential.Flags = static_cast<QUIC_CREDENTIAL_FLAGS>(
      QUIC_CREDENTIAL_FLAG_CLIENT |
      QUIC_CREDENTIAL_FLAG_INDICATE_CERTIFICATE_RECEIVED |
      QUIC_CREDENTIAL_FLAG_DEFER_CERTIFICATE_VALIDATION |
      QUIC_CREDENTIAL_FLAG_USE_PORTABLE_CERTIFICATES);
  status = transport->api->ConfigurationLoadCredential(
      transport->client_configuration, &credential);
  if (QUIC_FAILED(status)) {
    transport->api->ConfigurationClose(transport->client_configuration);
    transport->client_configuration = nullptr;
  }
  return status;
}

void DestroyTransport(AndroidRemoteTransport* transport) {
  if (transport == nullptr) return;
  if (transport->client_configuration != nullptr && transport->api != nullptr) {
    transport->api->ConfigurationClose(transport->client_configuration);
    transport->client_configuration = nullptr;
  }
  if (transport->registration != nullptr && transport->api != nullptr) {
    transport->api->RegistrationClose(transport->registration);
    transport->registration = nullptr;
  }
  if (transport->api != nullptr) {
    MsQuicClose(transport->api);
    transport->api = nullptr;
  }
  std::fill(transport->pinned_certificate.begin(),
            transport->pinned_certificate.end(), 0);
  delete transport;
}

}  // namespace

#if defined(__GNUC__)
#define AVACA_REMOTE_QUIC_API __attribute__((visibility("default")))
#else
#define AVACA_REMOTE_QUIC_API
#endif

extern "C" {

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_create_client(
    const uint8_t* pinned_server_certificate_sha256,
    uint32_t pinned_server_certificate_sha256_length,
    EventCallback callback,
    void* context,
    uint64_t* transport_handle) {
  if (pinned_server_certificate_sha256 == nullptr ||
      pinned_server_certificate_sha256_length != kChannelBindingLength ||
      callback == nullptr || transport_handle == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  *transport_handle = 0;
  auto* transport = new (std::nothrow) AndroidRemoteTransport();
  if (transport == nullptr) return QUIC_STATUS_OUT_OF_MEMORY;
  std::copy(pinned_server_certificate_sha256,
            pinned_server_certificate_sha256 + kChannelBindingLength,
            transport->pinned_certificate.begin());
  transport->callback = callback;
  transport->callback_context = context;

  auto status = MsQuicOpen2(&transport->api);
  if (QUIC_FAILED(status) || transport->api == nullptr) {
    LogQuicStatus("MsQuicOpen2 failed", status);
    DestroyTransport(transport);
    return status;
  }
  QUIC_REGISTRATION_CONFIG registration_config{};
  registration_config.AppName = "AVACA Remote Android";
  registration_config.ExecutionProfile = QUIC_EXECUTION_PROFILE_LOW_LATENCY;
  status = transport->api->RegistrationOpen(&registration_config,
                                            &transport->registration);
  if (QUIC_FAILED(status)) {
    LogQuicStatus("RegistrationOpen failed", status);
    DestroyTransport(transport);
    return status;
  }
  status = OpenClientConfiguration(transport);
  if (QUIC_FAILED(status)) {
    LogQuicStatus("OpenClientConfiguration failed", status);
    DestroyTransport(transport);
    return status;
  }
  *transport_handle = reinterpret_cast<uint64_t>(transport);
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_create_server(
    const uint8_t*,
    uint32_t,
    EventCallback,
    void*,
    uint64_t*) {
  return QUIC_STATUS_NOT_SUPPORTED;
}

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_listen(uint64_t,
                                                        uint16_t,
                                                        uint64_t*) {
  return QUIC_STATUS_NOT_SUPPORTED;
}

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_connect(
    uint64_t transport_handle,
    const char* host,
    uint16_t port,
    uint64_t* connection_handle) {
  auto* transport = reinterpret_cast<AndroidRemoteTransport*>(transport_handle);
  if (transport == nullptr || transport->api == nullptr || host == nullptr ||
      host[0] == '\0' || port == 0 || connection_handle == nullptr ||
      transport->closing || transport->client_configuration == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  *connection_handle = 0;
  auto* connection = new (std::nothrow) AndroidRemoteConnection();
  if (connection == nullptr) return QUIC_STATUS_OUT_OF_MEMORY;
  connection->transport = transport;
  HQUIC handle = nullptr;
  auto status = transport->api->ConnectionOpen(
      transport->registration, AndroidConnectionCallback, connection, &handle);
  if (QUIC_FAILED(status)) {
    LogQuicStatus("ConnectionOpen failed", status);
    delete connection;
    return status;
  }
  connection->handle = handle;
  transport->add_connection(connection);
  status = StartClientStream(connection);
  if (QUIC_FAILED(status)) {
    LogQuicStatus("StartClientStream failed", status);
    transport->api->ConnectionClose(handle);
    transport->remove_connection(handle);
    FreePendingSends(connection);
    delete connection;
    return status;
  }
  *connection_handle = reinterpret_cast<uint64_t>(connection);
  status = transport->api->ConnectionStart(
      handle, transport->client_configuration, QUIC_ADDRESS_FAMILY_UNSPEC, host,
      port);
  if (QUIC_FAILED(status)) {
    LogQuicStatus("ConnectionStart failed", status);
    transport->api->ConnectionClose(handle);
    transport->remove_connection(handle);
    FreePendingSends(connection);
    delete connection;
    *connection_handle = 0;
    return status;
  }
  // MsQuic returns QUIC_STATUS_PENDING (-2 on POSIX) for an asynchronously
  // started connection.  The Dart-facing ABI reserves zero for every
  // successfully queued operation, so normalize all non-failing statuses.
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_send(
    uint64_t connection_handle,
    const uint8_t* data,
    uint32_t length,
    uint64_t operation) {
  auto* connection = reinterpret_cast<AndroidRemoteConnection*>(connection_handle);
  if (connection == nullptr || data == nullptr || length == 0 || operation == 0 ||
      connection->transport == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  HQUIC stream = nullptr;
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    if (connection->closed || !connection->connected ||
        connection->stream == nullptr ||
        length > kMaxBufferedBytes -
                     std::min(connection->buffered_bytes, kMaxBufferedBytes)) {
      return connection->closed ? QUIC_STATUS_INVALID_STATE
                                : QUIC_STATUS_OUT_OF_MEMORY;
    }
    stream = connection->stream;
  }
  auto* pending = new (std::nothrow) AndroidPendingSend();
  if (pending == nullptr) return QUIC_STATUS_OUT_OF_MEMORY;
  pending->operation = operation;
  pending->length = length;
  pending->bytes.assign(data, data + length);
  pending->buffer.Length = length;
  pending->buffer.Buffer = pending->bytes.data();
  {
    std::lock_guard<std::mutex> lock(connection->mutex);
    if (connection->closed || connection->stream != stream ||
        connection->buffered_bytes > kMaxBufferedBytes - length) {
      FreePendingSend(pending);
      return QUIC_STATUS_INVALID_STATE;
    }
    connection->pending_sends.insert(pending);
    connection->buffered_bytes += length;
  }
  const auto status = connection->transport->api->StreamSend(
      stream, &pending->buffer, 1, QUIC_SEND_FLAG_NONE, pending);
  __android_log_print(ANDROID_LOG_INFO, "AVACA_QUIC",
                      "stream send queued op=%llu bytes=%u status=0x%08x",
                      static_cast<unsigned long long>(operation), length,
                      static_cast<uint32_t>(status));
  if (QUIC_FAILED(status)) {
    std::lock_guard<std::mutex> lock(connection->mutex);
    connection->pending_sends.erase(pending);
    connection->buffered_bytes =
        connection->buffered_bytes >= length
            ? connection->buffered_bytes - length
            : 0;
    FreePendingSend(pending);
    return status;
  }
  // StreamSend may return QUIC_STATUS_PENDING while the send is queued.  The
  // completion callback reports the eventual result to Dart; do not expose
  // the platform-specific pending value as a Dart error.
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_close_connection(
    uint64_t connection_handle) {
  auto* connection = reinterpret_cast<AndroidRemoteConnection*>(connection_handle);
  if (connection == nullptr || connection->transport == nullptr) {
    return QUIC_STATUS_SUCCESS;
  }
  ShutdownConnection(connection);
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_close_listener(uint64_t,
                                                                uint64_t) {
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t avaca_remote_quic_close(uint64_t transport_handle) {
  auto* transport = reinterpret_cast<AndroidRemoteTransport*>(transport_handle);
  if (transport == nullptr) return QUIC_STATUS_INVALID_PARAMETER;
  {
    std::lock_guard<std::mutex> lock(transport->mutex);
    if (transport->closing) return QUIC_STATUS_SUCCESS;
    transport->closing = true;
  }
  std::vector<AndroidRemoteConnection*> active;
  {
    std::lock_guard<std::mutex> lock(transport->mutex);
    active.reserve(transport->connections.size());
    for (const auto& entry : transport->connections) active.push_back(entry.second);
  }
  for (auto* connection : active) ShutdownConnection(connection);
  if (transport->registration != nullptr) {
    transport->api->RegistrationShutdown(
        transport->registration, QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT, 0);
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
  if (transport->api != nullptr) {
    MsQuicClose(transport->api);
    transport->api = nullptr;
  }
  std::fill(transport->pinned_certificate.begin(),
            transport->pinned_certificate.end(), 0);
  delete transport;
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API void avaca_remote_quic_free_buffer(const uint8_t* data) {
  if (data != nullptr) std::free(const_cast<uint8_t*>(data));
}

AVACA_REMOTE_QUIC_API void avaca_remote_quic_ack_receive(uint64_t,
                                                          uint64_t connection_object,
                                                          uint32_t length) {
  if (connection_object == 0 || length == 0) return;
  auto* connection = reinterpret_cast<AndroidRemoteConnection*>(connection_object);
  ReleaseInboundBytes(connection, length);
}

}  // extern "C"

#undef AVACA_REMOTE_QUIC_API

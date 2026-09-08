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
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <condition_variable>
#include <mutex>
#include <new>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include <msquic.h>

namespace {

constexpr uint32_t kChannelBindingLength = 32;
constexpr uint64_t kMaxBufferedBytes = 16ull * 1024ull * 1024ull;
constexpr uint32_t kMaxReceiveBytes = 16u * 1024u * 1024u;
constexpr char kAlpn[] = "avaca-remote/2";
constexpr char kExporterLabel[] = "EXPORTER-AVACA-REMOTE-V2";

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

// Native playback handles are process-local and deliberately contain no
// persisted path or grant material.  The read callback is supplied by the
// active QUIC resource session and is cancelled/closed before the handle is
// released.
struct AvacaRemotePlaybackStream {
  uint64_t resource_length = 0;
  AvacaRemotePlaybackReadAt read_at = nullptr;
  void* read_context = nullptr;
  bool cancelled = false;
  std::mutex mutex;
  std::condition_variable condition;
  uint64_t transport_handle = 0;
  uint64_t connection_handle = 0;
  bool native = false;
  bool connected = false;
  bool authenticated = false;
  bool opening = false;
  bool open_complete = false;
  bool read_in_flight = false;
  bool read_complete = false;
  bool read_cancelled = false;
  uint32_t active_read_calls = 0;
  bool closing = false;
  int32_t failure_status = QUIC_STATUS_SUCCESS;
  uint64_t next_request_id = 3;
  uint64_t active_request_id = 0;
  uint64_t active_offset = 0;
  uint32_t active_length = 0;
  std::string server_id;
  std::string client_id;
  std::string host;
  uint16_t port = 0;
  std::string playback_session_id;
  std::string resource_id;
  std::string resource_handle;
  std::vector<uint8_t> pairing_secret;
  std::vector<uint8_t> playback_grant;
  std::vector<uint8_t> certificate_pin;
  std::vector<uint8_t> receive_buffer;
  std::vector<uint8_t> read_bytes;
  std::vector<uint8_t> client_nonce;
  std::vector<uint8_t> server_nonce;
  std::vector<uint8_t> channel_binding;
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

constexpr uint8_t kProtocolVersion = 2;
constexpr uint32_t kApplicationMax = 1024u * 1024u;
constexpr uint32_t kPlaybackGrantLength = 32;
constexpr char kPlaybackDomain[] = "AVACA-REMOTE-V2/PLAYBACK";
constexpr char kPreAuthContext[] = "AVACA-REMOTE/PREAUTH/V2";

void Wipe(std::vector<uint8_t>* bytes) {
  if (bytes == nullptr || bytes->empty()) return;
  SecureZeroMemory(bytes->data(), bytes->size());
  bytes->clear();
}

void AppendUint16(std::vector<uint8_t>* output, uint16_t value) {
  output->push_back(static_cast<uint8_t>((value >> 8) & 0xff));
  output->push_back(static_cast<uint8_t>(value & 0xff));
}

void AppendUint64(std::vector<uint8_t>* output, uint64_t value) {
  for (int index = 7; index >= 0; --index) {
    output->push_back(static_cast<uint8_t>((value >> (index * 8)) & 0xff));
  }
}

uint64_t ReadUint64(const uint8_t* bytes) {
  uint64_t value = 0;
  for (int index = 0; index < 8; ++index) {
    value = (value << 8) | bytes[index];
  }
  return value;
}

void AppendField(std::vector<uint8_t>* output, const std::string& value) {
  AppendUint16(output, static_cast<uint16_t>(value.size()));
  output->insert(output->end(), value.begin(), value.end());
}

void AppendField(std::vector<uint8_t>* output,
                 const std::vector<uint8_t>& value) {
  if (value.size() > 0xffff) return;
  AppendUint16(output, static_cast<uint16_t>(value.size()));
  output->insert(output->end(), value.begin(), value.end());
}

std::vector<uint8_t> BytesFromString(const std::string& value) {
  std::vector<uint8_t> bytes;
  bytes.reserve(value.size());
  for (const char character : value) {
    bytes.push_back(static_cast<uint8_t>(
        static_cast<unsigned char>(character)));
  }
  return bytes;
}

bool HmacSha256(const std::vector<uint8_t>& key,
                const std::vector<uint8_t>& message,
                std::vector<uint8_t>* output) {
  if (output == nullptr || key.empty()) return false;
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr,
                                  BCRYPT_ALG_HANDLE_HMAC_FLAG) != 0) {
    return false;
  }
  DWORD object_length = 0;
  DWORD result_length = 0;
  const auto property_status = BCryptGetProperty(
      algorithm, BCRYPT_OBJECT_LENGTH,
      reinterpret_cast<PUCHAR>(&object_length), sizeof(object_length),
      &result_length, 0);
  if (property_status != 0 || object_length == 0) {
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return false;
  }
  std::vector<uint8_t> object(object_length);
  BCRYPT_HASH_HANDLE hash = nullptr;
  auto status = BCryptCreateHash(
      algorithm, &hash, object.data(), object_length,
      const_cast<PUCHAR>(key.data()), static_cast<ULONG>(key.size()), 0);
  if (status == 0 && !message.empty()) {
    status = BCryptHashData(hash, const_cast<PUCHAR>(message.data()),
                            static_cast<ULONG>(message.size()), 0);
  }
  output->assign(32, 0);
  if (status == 0) {
    status = BCryptFinishHash(hash, output->data(), 32, 0);
  }
  if (hash != nullptr) BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(algorithm, 0);
  if (status != 0) {
    Wipe(output);
    return false;
  }
  return true;
}

bool RandomBytes(std::vector<uint8_t>* output, size_t length) {
  if (output == nullptr) return false;
  output->assign(length, 0);
  return length == 0 ||
         BCryptGenRandom(nullptr, output->data(), static_cast<ULONG>(length),
                         BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0;
}

std::string Base64UrlEncode(const std::vector<uint8_t>& bytes) {
  static constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  std::string result;
  result.reserve((bytes.size() * 4 + 2) / 3);
  uint32_t accumulator = 0;
  int bits = 0;
  for (const auto value : bytes) {
    accumulator = (accumulator << 8) | value;
    bits += 8;
    while (bits >= 6) {
      bits -= 6;
      result.push_back(alphabet[(accumulator >> bits) & 0x3f]);
    }
  }
  if (bits > 0) result.push_back(alphabet[(accumulator << (6 - bits)) & 0x3f]);
  return result;
}

std::optional<std::vector<uint8_t>> Base64UrlDecode(const std::string& value) {
  std::vector<uint8_t> result;
  uint32_t accumulator = 0;
  int bits = 0;
  auto decode = [](char value) -> int {
    if (value >= 'A' && value <= 'Z') return value - 'A';
    if (value >= 'a' && value <= 'z') return value - 'a' + 26;
    if (value >= '0' && value <= '9') return value - '0' + 52;
    if (value == '-') return 62;
    if (value == '_') return 63;
    return -1;
  };
  for (const auto character : value) {
    const auto digit = decode(character);
    if (digit < 0) return std::nullopt;
    accumulator = (accumulator << 6) | static_cast<uint32_t>(digit);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      result.push_back(static_cast<uint8_t>((accumulator >> bits) & 0xff));
    }
  }
  if (bits >= 6 || (bits > 0 && (accumulator & ((1u << bits) - 1u)) != 0)) {
    return std::nullopt;
  }
  return result;
}

std::optional<std::string> JsonString(const std::string& json,
                                      const char* key) {
  const std::string prefix = std::string("\"") + key + "\":\"";
  const auto start = json.find(prefix);
  if (start == std::string::npos) return std::nullopt;
  const auto value_start = start + prefix.size();
  const auto value_end = json.find('"', value_start);
  if (value_end == std::string::npos) return std::nullopt;
  const auto value = json.substr(value_start, value_end - value_start);
  if (value.find('\\') != std::string::npos) return std::nullopt;
  return value;
}

std::optional<uint64_t> JsonUint64(const std::string& json, const char* key) {
  const std::string prefix = std::string("\"") + key + "\":";
  const auto start = json.find(prefix);
  if (start == std::string::npos) return std::nullopt;
  const auto value_start = start + prefix.size();
  size_t value_end = value_start;
  while (value_end < json.size() &&
         json[value_end] >= '0' && json[value_end] <= '9') {
    value_end++;
  }
  if (value_end == value_start) return std::nullopt;
  uint64_t value = 0;
  for (size_t index = value_start; index < value_end; ++index) {
    const auto digit = static_cast<uint64_t>(json[index] - '0');
    if (value > (UINT64_MAX - digit) / 10) return std::nullopt;
    value = value * 10 + digit;
  }
  return value;
}

std::vector<uint8_t> JsonBytes(const std::string& json, const char* key) {
  const auto encoded = JsonString(json, key);
  if (!encoded) return {};
  const auto decoded = Base64UrlDecode(*encoded);
  return decoded.value_or(std::vector<uint8_t>());
}

std::vector<uint8_t> BuildFrame(uint8_t opcode,
                                uint64_t request_id,
                                const std::string& payload) {
  std::vector<uint8_t> frame(16 + payload.size(), 0);
  frame[0] = kProtocolVersion;
  frame[1] = opcode;
  frame[4] = static_cast<uint8_t>((payload.size() >> 24) & 0xff);
  frame[5] = static_cast<uint8_t>((payload.size() >> 16) & 0xff);
  frame[6] = static_cast<uint8_t>((payload.size() >> 8) & 0xff);
  frame[7] = static_cast<uint8_t>(payload.size() & 0xff);
  for (int index = 0; index < 8; ++index) {
    frame[8 + index] =
        static_cast<uint8_t>((request_id >> ((7 - index) * 8)) & 0xff);
  }
  std::memcpy(frame.data() + 16, payload.data(), payload.size());
  return frame;
}

std::string JsonQuote(const std::string& value) {
  std::string result;
  result.reserve(value.size() + 2);
  result.push_back('"');
  for (const auto character : value) {
    switch (character) {
      case '"':
        result += "\\\"";
        break;
      case '\\':
        result += "\\\\";
        break;
      case '\b':
        result += "\\b";
        break;
      case '\f':
        result += "\\f";
        break;
      case '\n':
        result += "\\n";
        break;
      case '\r':
        result += "\\r";
        break;
      case '\t':
        result += "\\t";
        break;
      default:
        if (static_cast<unsigned char>(character) < 0x20) {
          result += "\\u00";
          constexpr char hex[] = "0123456789abcdef";
          result.push_back(hex[(static_cast<unsigned char>(character) >> 4) &
                               0x0f]);
          result.push_back(hex[static_cast<unsigned char>(character) & 0x0f]);
        } else {
          result.push_back(character);
        }
        break;
    }
  }
  result.push_back('"');
  return result;
}

std::vector<uint8_t> BuildTranscript(const char* label,
                                     const std::string& domain,
                                     const std::vector<uint8_t>& binding,
                                     const std::vector<std::vector<uint8_t>>& fields) {
  std::vector<uint8_t> transcript;
  transcript.insert(transcript.end(), kPreAuthContext,
                    kPreAuthContext + std::strlen(kPreAuthContext));
  transcript.push_back(0);
  AppendField(&transcript, std::string(label));
  AppendField(&transcript, domain);
  AppendField(&transcript, binding);
  for (const auto& field : fields) AppendField(&transcript, field);
  return transcript;
}

bool SendNativeFrame(AvacaRemotePlaybackStream* stream,
                     uint8_t opcode,
                     uint64_t request_id,
                     const std::string& payload) {
  if (stream == nullptr || stream->connection_handle == 0) return false;
  auto frame = BuildFrame(opcode, request_id, payload);
  return avaca_remote_quic_send(stream->connection_handle, frame.data(),
                                static_cast<uint32_t>(frame.size()),
                                request_id) == QUIC_STATUS_SUCCESS;
}

void FailNativePlayback(AvacaRemotePlaybackStream* stream, int32_t status) {
  if (stream == nullptr) return;
  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (stream->failure_status == QUIC_STATUS_SUCCESS) {
      stream->failure_status = status;
    }
    stream->condition.notify_all();
  }
}

bool SendNativeClientHello(AvacaRemotePlaybackStream* stream) {
  if (stream == nullptr || stream->pairing_secret.size() != 32 ||
      stream->client_nonce.size() != 32 || stream->channel_binding.size() != 32) {
    return false;
  }
  const auto transcript = BuildTranscript(
      "client-hello", kPlaybackDomain, stream->channel_binding,
      {BytesFromString(stream->client_id),
       stream->client_nonce});
  std::vector<uint8_t> proof;
  if (!HmacSha256(stream->pairing_secret, transcript, &proof)) return false;
  const std::string payload =
      std::string("{\"clientId\":") + JsonQuote(stream->client_id) +
      ",\"clientNonce\":" + JsonQuote(Base64UrlEncode(stream->client_nonce)) +
      ",\"proof\":" + JsonQuote(Base64UrlEncode(proof)) + "}";
  Wipe(&proof);
  return SendNativeFrame(stream, 0x01, 1, payload);
}

bool SendNativeAcceptance(AvacaRemotePlaybackStream* stream,
                          const std::string& server_id,
                          const std::vector<uint8_t>& server_nonce) {
  const auto transcript = BuildTranscript(
      "authenticated", kPlaybackDomain, stream->channel_binding,
      {BytesFromString(server_id),
       BytesFromString(stream->client_id),
       stream->client_nonce, server_nonce});
  std::vector<uint8_t> proof;
  if (!HmacSha256(stream->pairing_secret, transcript, &proof)) return false;
  const std::string payload =
      std::string("{\"serverId\":") + JsonQuote(server_id) +
      ",\"clientId\":" + JsonQuote(stream->client_id) +
      ",\"proof\":" + JsonQuote(Base64UrlEncode(proof)) + "}";
  Wipe(&proof);
  return SendNativeFrame(stream, 0x03, 2, payload);
}

void HandleNativeApplicationFrame(AvacaRemotePlaybackStream* stream,
                                  uint8_t opcode,
                                  uint64_t request_id,
                                  const std::string& payload) {
  if (stream == nullptr) return;
  if (opcode == 0x02) {
    const auto server_id = JsonString(payload, "serverId");
    const auto client_id = JsonString(payload, "clientId");
    const auto server_nonce_encoded = JsonString(payload, "serverNonce");
    const auto proof_encoded = JsonString(payload, "proof");
    if (!server_id || !client_id || !server_nonce_encoded || !proof_encoded ||
        *server_id != stream->server_id || *client_id != stream->client_id) {
      FailNativePlayback(stream, QUIC_STATUS_BAD_CERTIFICATE);
      return;
    }
    const auto server_nonce = Base64UrlDecode(*server_nonce_encoded);
    const auto proof = Base64UrlDecode(*proof_encoded);
    if (!server_nonce || server_nonce->size() != 32 || !proof ||
        proof->size() != 32) {
      FailNativePlayback(stream, QUIC_STATUS_INVALID_PARAMETER);
      return;
    }
    const auto transcript = BuildTranscript(
        "server-hello", kPlaybackDomain, stream->channel_binding,
        {BytesFromString(*server_id),
         BytesFromString(stream->client_id),
         stream->client_nonce, *server_nonce});
    std::vector<uint8_t> expected;
    if (!HmacSha256(stream->pairing_secret, transcript, &expected) ||
        !ConstantTimeEquals(expected.data(), proof->data(), 32)) {
      Wipe(&expected);
      FailNativePlayback(stream, QUIC_STATUS_BAD_CERTIFICATE);
      return;
    }
    const bool sent = SendNativeAcceptance(stream, *server_id, *server_nonce);
    Wipe(&expected);
    if (!sent) FailNativePlayback(stream, QUIC_STATUS_ABORTED);
    return;
  }
  if (opcode == 0x05) {
    const auto server_id = JsonString(payload, "serverId");
    const auto client_id = JsonString(payload, "clientId");
    const auto proof_encoded = JsonString(payload, "proof");
    const auto proof = proof_encoded ? Base64UrlDecode(*proof_encoded)
                                     : std::optional<std::vector<uint8_t>>();
    if (!server_id || !client_id || !proof || proof->size() != 32 ||
        *server_id != stream->server_id || *client_id != stream->client_id) {
      FailNativePlayback(stream, QUIC_STATUS_BAD_CERTIFICATE);
      return;
    }
    // The server's authenticated response repeats the client acceptance proof.
    // Rebuild it from the nonce pair retained during the handshake.
    const auto transcript = BuildTranscript(
        "authenticated", kPlaybackDomain, stream->channel_binding,
        {BytesFromString(stream->server_id),
         BytesFromString(stream->client_id),
         stream->client_nonce, stream->server_nonce});
    std::vector<uint8_t> expected;
    if (!HmacSha256(stream->pairing_secret, transcript, &expected) ||
        !ConstantTimeEquals(expected.data(), proof->data(), 32)) {
      Wipe(&expected);
      FailNativePlayback(stream, QUIC_STATUS_BAD_CERTIFICATE);
      return;
    }
    Wipe(&expected);
    {
      std::lock_guard<std::mutex> lock(stream->mutex);
      stream->authenticated = true;
      stream->condition.notify_all();
    }
    return;
  }
  if (opcode == 0x41) {
    const auto handle = JsonString(payload, "resourceHandle");
    const auto content_length = JsonUint64(payload, "contentLength");
    if (!handle || handle->empty() || !content_length) {
      FailNativePlayback(stream, QUIC_STATUS_INVALID_PARAMETER);
      return;
    }
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (request_id != 3 || !stream->opening) return;
    stream->resource_handle = *handle;
    stream->resource_length = *content_length;
    stream->open_complete = true;
    stream->opening = false;
    stream->condition.notify_all();
    return;
  }
  if (opcode == 0x43) {
    const auto offset = JsonUint64(payload, "offset");
    const auto bytes = JsonBytes(payload, "bytes");
    if (!offset || bytes.size() > stream->active_length) {
      FailNativePlayback(stream, QUIC_STATUS_INVALID_PARAMETER);
      return;
    }
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (stream->read_cancelled && request_id == stream->active_request_id) {
      return;
    }
    if (!stream->read_in_flight || request_id != stream->active_request_id ||
        *offset != stream->active_offset) {
      FailNativePlayback(stream, QUIC_STATUS_INVALID_STATE);
      return;
    }
    stream->read_bytes = bytes;
    stream->read_complete = true;
    stream->read_in_flight = false;
    stream->condition.notify_all();
    return;
  }
  if (opcode == 0x7f) {
    FailNativePlayback(stream, QUIC_STATUS_ABORTED);
    std::lock_guard<std::mutex> lock(stream->mutex);
    stream->opening = false;
    stream->read_in_flight = false;
    stream->read_cancelled = true;
    stream->condition.notify_all();
  }
}

void ProcessNativeBytes(AvacaRemotePlaybackStream* stream,
                        const uint8_t* data,
                        uint32_t length) {
  if (stream == nullptr || (length > 0 && data == nullptr)) return;
  std::vector<std::vector<uint8_t>> frames;
  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (length > 0) {
      stream->receive_buffer.insert(stream->receive_buffer.end(), data,
                                    data + length);
    }
    if (stream->receive_buffer.size() > kMaxReceiveBytes) {
      stream->failure_status = QUIC_STATUS_OUT_OF_MEMORY;
      stream->condition.notify_all();
      return;
    }
    while (stream->receive_buffer.size() >= 16) {
      if (stream->receive_buffer[0] != kProtocolVersion ||
          stream->receive_buffer[2] != 0 || stream->receive_buffer[3] != 0) {
        stream->failure_status = QUIC_STATUS_INVALID_PARAMETER;
        stream->condition.notify_all();
        return;
      }
      const auto payload_length =
          (static_cast<uint32_t>(stream->receive_buffer[4]) << 24) |
          (static_cast<uint32_t>(stream->receive_buffer[5]) << 16) |
          (static_cast<uint32_t>(stream->receive_buffer[6]) << 8) |
          stream->receive_buffer[7];
      if (payload_length > kApplicationMax) {
        stream->failure_status = QUIC_STATUS_OUT_OF_MEMORY;
        stream->condition.notify_all();
        return;
      }
      if (stream->receive_buffer.size() < 16u + payload_length) break;
      std::vector<uint8_t> frame(
          stream->receive_buffer.begin(),
          stream->receive_buffer.begin() + 16u + payload_length);
      stream->receive_buffer.erase(
          stream->receive_buffer.begin(),
          stream->receive_buffer.begin() + 16u + payload_length);
      frames.push_back(std::move(frame));
    }
  }
  for (const auto& frame : frames) {
    const auto opcode = frame[1];
    const auto request_id = ReadUint64(frame.data() + 8);
    const auto payload = std::string(
        reinterpret_cast<const char*>(frame.data() + 16),
        frame.size() - 16);
    if (opcode == 0x02) {
      const auto server_nonce = JsonBytes(payload, "serverNonce");
      std::lock_guard<std::mutex> lock(stream->mutex);
      stream->server_nonce = server_nonce;
    }
    HandleNativeApplicationFrame(stream, opcode, request_id, payload);
  }
}

void AVACA_REMOTE_QUIC_CALL NativePlaybackEventCallback(
    void* context,
    uint64_t object,
    uint32_t event,
    int32_t status,
    uint64_t operation,
    const uint8_t* data,
    uint32_t length,
    uint8_t flags) {
  auto* stream = static_cast<AvacaRemotePlaybackStream*>(context);
  if (stream == nullptr) return;
  if (event == AVACA_REMOTE_QUIC_EVENT_CONNECTED) {
    {
      std::lock_guard<std::mutex> lock(stream->mutex);
      stream->connection_handle = object;
      stream->connected = true;
      if (length != kChannelBindingLength || data == nullptr) {
        stream->channel_binding.clear();
      } else {
        stream->channel_binding.assign(data, data + length);
      }
    }
    if (!SendNativeClientHello(stream)) {
      FailNativePlayback(stream, QUIC_STATUS_ABORTED);
    }
  } else if (event == AVACA_REMOTE_QUIC_EVENT_DATA) {
    ProcessNativeBytes(stream, data, length);
    avaca_remote_quic_ack_receive(stream->transport_handle, object, length);
  } else if (event == AVACA_REMOTE_QUIC_EVENT_ERROR) {
    FailNativePlayback(stream, status);
  } else if (event == AVACA_REMOTE_QUIC_EVENT_CLOSED) {
    FailNativePlayback(stream, status == QUIC_STATUS_SUCCESS
                                  ? QUIC_STATUS_ABORTED
                                  : status);
  }
  if (data != nullptr) avaca_remote_quic_free_buffer(data);
  (void)operation;
  (void)flags;
}

bool IsSafeHandshakeId(const char* value, uint32_t length) {
  if (value == nullptr || length == 0 || length > 256) return false;
  for (uint32_t index = 0; index < length; ++index) {
    const auto character = static_cast<unsigned char>(value[index]);
    const bool alpha_numeric =
        (character >= 'A' && character <= 'Z') ||
        (character >= 'a' && character <= 'z') ||
        (character >= '0' && character <= '9');
    if (!alpha_numeric && character != '.' && character != '_' &&
        character != '~' && character != '-') {
      return false;
    }
  }
  return true;
}

bool HasNoNulls(const char* value, uint32_t length) {
  if (value == nullptr || length == 0) return false;
  for (uint32_t index = 0; index < length; ++index) {
    if (value[index] == '\0') return false;
  }
  return true;
}

bool ValidateNativeProfile(const AvacaRemoteClientProfile* profile) {
  return profile != nullptr &&
         IsSafeHandshakeId(profile->server_id, profile->server_id_length) &&
         IsSafeHandshakeId(profile->client_id, profile->client_id_length) &&
         HasNoNulls(profile->host, profile->host_length) &&
         profile->host_length <= 255 && profile->port != 0 &&
         profile->certificate_sha256_pin != nullptr &&
         profile->certificate_sha256_pin_length == kChannelBindingLength &&
         profile->pairing_secret != nullptr &&
         profile->pairing_secret_length == kPlaybackGrantLength;
}

bool ValidateNativeDescriptor(const AvacaRemotePlaybackDescriptor* descriptor) {
  if (descriptor == nullptr || descriptor->resource_id == nullptr ||
      descriptor->resource_id_length == 0 ||
      descriptor->resource_id_length > 256 ||
      descriptor->playback_session_id == nullptr ||
      !IsSafeHandshakeId(descriptor->playback_session_id,
                         descriptor->playback_session_id_length) ||
      descriptor->playback_grant == nullptr ||
      descriptor->playback_grant_length != kPlaybackGrantLength) {
    return false;
  }
  for (uint32_t index = 0; index < descriptor->resource_id_length; ++index) {
    if (descriptor->resource_id[index] == 0) return false;
  }
  return true;
}

void CloseNativeHandles(AvacaRemotePlaybackStream* stream) {
  if (stream == nullptr) return;
  const auto connection = stream->connection_handle;
  const auto transport = stream->transport_handle;
  if (connection != 0) {
    avaca_remote_quic_close_connection(connection);
  }
  if (transport != 0) {
    avaca_remote_quic_close(transport);
  }
  stream->connection_handle = 0;
  stream->transport_handle = 0;
}

int32_t FinishNativeRead(AvacaRemotePlaybackStream* stream,
                         int32_t status,
                         uint32_t* bytes_read) {
  if (stream == nullptr) return status;
  std::lock_guard<std::mutex> lock(stream->mutex);
  stream->read_in_flight = false;
  if (stream->active_read_calls > 0) --stream->active_read_calls;
  stream->condition.notify_all();
  if (bytes_read != nullptr && status != QUIC_STATUS_SUCCESS) {
    *bytes_read = 0;
  }
  return status;
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
  if ((pinned_server_certificate_sha256_length != 0 &&
       pinned_server_certificate_sha256 == nullptr) ||
      (pinned_server_certificate_sha256_length != 0 &&
       pinned_server_certificate_sha256_length != kChannelBindingLength) ||
      (server_certificate_sha1_length != 0 &&
       (server_certificate_sha1 == nullptr || server_certificate_sha1_length != 20)) ||
      (pinned_server_certificate_sha256_length == 0 &&
       server_certificate_sha1_length == 0) ||
      callback == nullptr || transport_handle == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }

  auto* transport = new (std::nothrow) AvacaRemoteQuicTransport();
  if (transport == nullptr) {
    return QUIC_STATUS_OUT_OF_MEMORY;
  }
  if (pinned_server_certificate_sha256_length == kChannelBindingLength) {
    std::memcpy(
        transport->pinned_server_certificate_sha256,
        pinned_server_certificate_sha256,
        kChannelBindingLength);
  }
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
  if (pinned_server_certificate_sha256_length == kChannelBindingLength) {
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
avaca_remote_quic_create_server(
    const uint8_t* server_certificate_sha1,
    uint32_t server_certificate_sha1_length,
    AvacaRemoteQuicEventCallback callback,
    void* context,
    uint64_t* transport_handle) {
  return avaca_remote_quic_create(
      nullptr,
      0,
      server_certificate_sha1,
      server_certificate_sha1_length,
      callback,
      context,
      transport_handle);
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_create_client(
    const uint8_t* pinned_server_certificate_sha256,
    uint32_t pinned_server_certificate_sha256_length,
    AvacaRemoteQuicEventCallback callback,
    void* context,
    uint64_t* transport_handle) {
  return avaca_remote_quic_create(
      pinned_server_certificate_sha256,
      pinned_server_certificate_sha256_length,
      nullptr,
      0,
      callback,
      context,
      transport_handle);
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

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_open(
    uint64_t transport_handle,
    const AvacaRemotePlaybackDescriptor* descriptor,
    AvacaRemotePlaybackReadAt read_at,
    void* read_context,
    uint64_t* stream_handle) {
  if (transport_handle == 0 || descriptor == nullptr ||
      descriptor->resource_id == nullptr || descriptor->resource_id_length == 0 ||
      descriptor->resource_id_length > 128 || read_at == nullptr ||
      stream_handle == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  auto* stream = new (std::nothrow) AvacaRemotePlaybackStream();
  if (stream == nullptr) return QUIC_STATUS_OUT_OF_MEMORY;
  stream->resource_length = descriptor->resource_length;
  stream->read_at = read_at;
  stream->read_context = read_context;
  *stream_handle = reinterpret_cast<uint64_t>(stream);
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_open_native(
    const AvacaRemoteClientProfile* profile,
    const AvacaRemotePlaybackDescriptor* descriptor,
    uint64_t* stream_handle) {
  if (!ValidateNativeProfile(profile) ||
      !ValidateNativeDescriptor(descriptor) || stream_handle == nullptr) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  *stream_handle = 0;

  auto* stream = new (std::nothrow) AvacaRemotePlaybackStream();
  if (stream == nullptr) return QUIC_STATUS_OUT_OF_MEMORY;
  stream->native = true;
  stream->resource_length = descriptor->resource_length;
  stream->server_id.assign(profile->server_id, profile->server_id_length);
  stream->client_id.assign(profile->client_id, profile->client_id_length);
  stream->host.assign(profile->host, profile->host_length);
  stream->port = profile->port;
  stream->playback_session_id.assign(descriptor->playback_session_id,
                                     descriptor->playback_session_id_length);
  stream->resource_id.assign(
      reinterpret_cast<const char*>(descriptor->resource_id),
      descriptor->resource_id_length);
  stream->pairing_secret.assign(
      profile->pairing_secret,
      profile->pairing_secret + profile->pairing_secret_length);
  stream->playback_grant.assign(
      descriptor->playback_grant,
      descriptor->playback_grant + descriptor->playback_grant_length);
  stream->certificate_pin.assign(
      profile->certificate_sha256_pin,
      profile->certificate_sha256_pin + profile->certificate_sha256_pin_length);
  if (!RandomBytes(&stream->client_nonce, 32)) {
    Wipe(&stream->pairing_secret);
    Wipe(&stream->playback_grant);
    Wipe(&stream->certificate_pin);
    delete stream;
    return QUIC_STATUS_INTERNAL_ERROR;
  }

  uint64_t transport = 0;
  auto status = avaca_remote_quic_create_client(
      stream->certificate_pin.data(),
      static_cast<uint32_t>(stream->certificate_pin.size()),
      NativePlaybackEventCallback,
      stream,
      &transport);
  if (status != QUIC_STATUS_SUCCESS) {
    Wipe(&stream->pairing_secret);
    Wipe(&stream->playback_grant);
    Wipe(&stream->certificate_pin);
    delete stream;
    return status;
  }
  stream->transport_handle = transport;

  uint64_t connection = 0;
  status = avaca_remote_quic_connect(
      transport, stream->host.c_str(), stream->port, &connection);
  if (status != QUIC_STATUS_SUCCESS) {
    CloseNativeHandles(stream);
    Wipe(&stream->pairing_secret);
    Wipe(&stream->playback_grant);
    Wipe(&stream->certificate_pin);
    Wipe(&stream->client_nonce);
    delete stream;
    return status;
  }
  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (stream->connection_handle == 0) {
      stream->connection_handle = connection;
    }
  }

  int32_t failure = QUIC_STATUS_SUCCESS;
  {
    std::unique_lock<std::mutex> lock(stream->mutex);
    const bool ready = stream->condition.wait_for(
        lock, std::chrono::seconds(15), [&stream]() {
          return stream->authenticated ||
                 stream->failure_status != QUIC_STATUS_SUCCESS ||
                 stream->closing;
        });
    if (!ready || !stream->authenticated) {
      failure = stream->failure_status == QUIC_STATUS_SUCCESS
                    ? QUIC_STATUS_ABORTED
                    : stream->failure_status;
    }
  }
  if (failure != QUIC_STATUS_SUCCESS) {
    {
      std::lock_guard<std::mutex> lock(stream->mutex);
      stream->closing = true;
      stream->condition.notify_all();
    }
    CloseNativeHandles(stream);
    Wipe(&stream->pairing_secret);
    Wipe(&stream->playback_grant);
    Wipe(&stream->certificate_pin);
    Wipe(&stream->client_nonce);
    Wipe(&stream->server_nonce);
    Wipe(&stream->channel_binding);
    delete stream;
    return failure;
  }

  const std::string open_payload =
      std::string("{\"playbackSessionId\":") +
      JsonQuote(stream->playback_session_id) +
      ",\"resourceId\":" + JsonQuote(stream->resource_id) +
      ",\"playbackGrant\":" +
      JsonQuote(Base64UrlEncode(stream->playback_grant)) + "}";
  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    stream->opening = true;
    stream->open_complete = false;
  }
  if (!SendNativeFrame(stream, 0x40, 3, open_payload)) {
    failure = QUIC_STATUS_ABORTED;
  } else {
    std::unique_lock<std::mutex> lock(stream->mutex);
    const bool opened = stream->condition.wait_for(
        lock, std::chrono::seconds(15), [&stream]() {
          return stream->open_complete ||
                 stream->failure_status != QUIC_STATUS_SUCCESS ||
                 stream->closing;
        });
    if (!opened || !stream->open_complete) {
      failure = stream->failure_status == QUIC_STATUS_SUCCESS
                    ? QUIC_STATUS_ABORTED
                    : stream->failure_status;
    }
  }
  if (failure != QUIC_STATUS_SUCCESS) {
    {
      std::lock_guard<std::mutex> lock(stream->mutex);
      stream->closing = true;
      stream->condition.notify_all();
    }
    CloseNativeHandles(stream);
    Wipe(&stream->pairing_secret);
    Wipe(&stream->playback_grant);
    Wipe(&stream->certificate_pin);
    Wipe(&stream->client_nonce);
    Wipe(&stream->server_nonce);
    Wipe(&stream->channel_binding);
    delete stream;
    return failure;
  }
  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    stream->next_request_id = 4;
  }
  *stream_handle = reinterpret_cast<uint64_t>(stream);
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_read_at(
    uint64_t stream_handle,
    uint64_t offset,
    uint8_t* destination,
    uint32_t length,
    uint32_t* bytes_read) {
  auto* stream = reinterpret_cast<AvacaRemotePlaybackStream*>(stream_handle);
  if (stream == nullptr || bytes_read == nullptr ||
      (destination == nullptr && length != 0) ||
      length > 4u * 1024u * 1024u) {
    return QUIC_STATUS_INVALID_PARAMETER;
  }
  *bytes_read = 0;

  if (stream->native) {
    uint64_t request_id = 0;
    {
      std::lock_guard<std::mutex> lock(stream->mutex);
      if (stream->closing || !stream->authenticated ||
          !stream->open_complete || stream->failure_status != QUIC_STATUS_SUCCESS) {
        return stream->failure_status == QUIC_STATUS_SUCCESS
                   ? QUIC_STATUS_ABORTED
                   : stream->failure_status;
      }
      if (offset > stream->resource_length ||
          length > stream->resource_length - offset ||
          stream->read_in_flight) {
        return QUIC_STATUS_INVALID_PARAMETER;
      }
      ++stream->active_read_calls;
      stream->read_in_flight = true;
      stream->read_complete = false;
      stream->read_cancelled = false;
      stream->read_bytes.clear();
      stream->active_offset = offset;
      stream->active_length = length;
      request_id = stream->next_request_id++;
      stream->active_request_id = request_id;
    }

    if (length == 0) {
      return FinishNativeRead(stream, QUIC_STATUS_SUCCESS, bytes_read);
    }
    const std::string payload =
        std::string("{\"resourceHandle\":") +
        JsonQuote(stream->resource_handle) + ",\"offset\":" +
        std::to_string(offset) + ",\"length\":" +
        std::to_string(length) + "}";
    if (!SendNativeFrame(stream, 0x42, request_id, payload)) {
      return FinishNativeRead(stream, QUIC_STATUS_ABORTED, bytes_read);
    }

    int32_t result = QUIC_STATUS_SUCCESS;
    {
      std::unique_lock<std::mutex> lock(stream->mutex);
      stream->condition.wait(lock, [&stream]() {
        return stream->read_complete || stream->read_cancelled ||
               stream->failure_status != QUIC_STATUS_SUCCESS ||
               stream->closing;
      });
      if (stream->failure_status != QUIC_STATUS_SUCCESS) {
        result = stream->failure_status;
      } else if (stream->read_cancelled || stream->closing ||
                 !stream->read_complete) {
        result = QUIC_STATUS_ABORTED;
      } else if (stream->read_bytes.size() > length) {
        result = QUIC_STATUS_INVALID_PARAMETER;
      } else {
        std::memcpy(destination, stream->read_bytes.data(),
                    stream->read_bytes.size());
        *bytes_read = static_cast<uint32_t>(stream->read_bytes.size());
      }
    }
    return FinishNativeRead(stream, result, bytes_read);
  }

  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (stream->cancelled || offset > stream->resource_length ||
        length > stream->resource_length - offset) {
      return QUIC_STATUS_ABORTED;
    }
  }
  if (stream->read_at == nullptr) return QUIC_STATUS_INVALID_STATE;
  return stream->read_at(
      stream->read_context, offset, destination, length, bytes_read);
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_cancel(uint64_t stream_handle) {
  auto* stream = reinterpret_cast<AvacaRemotePlaybackStream*>(stream_handle);
  if (stream == nullptr) return QUIC_STATUS_INVALID_PARAMETER;
  if (!stream->native) {
    std::lock_guard<std::mutex> lock(stream->mutex);
    stream->cancelled = true;
    return QUIC_STATUS_SUCCESS;
  }

  uint64_t target_request_id = 0;
  uint64_t cancel_request_id = 0;
  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    if (stream->closing || !stream->read_in_flight) {
      return QUIC_STATUS_SUCCESS;
    }
    target_request_id = stream->active_request_id;
    cancel_request_id = stream->next_request_id++;
    stream->read_cancelled = true;
    stream->condition.notify_all();
  }
  const std::string payload =
      std::string("{\"targetRequestId\":") +
      std::to_string(target_request_id) + "}";
  if (!SendNativeFrame(stream, 0x44, cancel_request_id, payload)) {
    FailNativePlayback(stream, QUIC_STATUS_ABORTED);
    return QUIC_STATUS_ABORTED;
  }
  return QUIC_STATUS_SUCCESS;
}

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_close(uint64_t stream_handle) {
  auto* stream = reinterpret_cast<AvacaRemotePlaybackStream*>(stream_handle);
  if (stream == nullptr) return QUIC_STATUS_SUCCESS;
  if (stream->native) {
    std::string resource_handle;
    uint64_t connection = 0;
    uint64_t close_request_id = 0;
    {
      std::unique_lock<std::mutex> lock(stream->mutex);
      stream->closing = true;
      stream->cancelled = true;
      stream->read_cancelled = true;
      stream->condition.notify_all();
      stream->condition.wait(lock, [&stream]() {
        return stream->active_read_calls == 0;
      });
      connection = stream->connection_handle;
      if (stream->open_complete && !stream->resource_handle.empty()) {
        resource_handle = stream->resource_handle;
        close_request_id = stream->next_request_id++;
      }
    }
    if (connection != 0 && !resource_handle.empty()) {
      const std::string payload =
          std::string("{\"resourceHandle\":") +
          JsonQuote(resource_handle) + "}";
      SendNativeFrame(stream, 0x45, close_request_id, payload);
    }
    CloseNativeHandles(stream);
    Wipe(&stream->pairing_secret);
    Wipe(&stream->playback_grant);
    Wipe(&stream->certificate_pin);
    Wipe(&stream->client_nonce);
    Wipe(&stream->server_nonce);
    Wipe(&stream->channel_binding);
    delete stream;
    return QUIC_STATUS_SUCCESS;
  }
  {
    std::lock_guard<std::mutex> lock(stream->mutex);
    stream->cancelled = true;
    stream->read_at = nullptr;
    stream->read_context = nullptr;
  }
  delete stream;
  return QUIC_STATUS_SUCCESS;
}

}  // extern "C"

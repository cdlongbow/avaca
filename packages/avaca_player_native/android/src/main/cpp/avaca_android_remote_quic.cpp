#include <jni.h>

#ifndef QUIC_API_ENABLE_PREVIEW_FEATURES
#define QUIC_API_ENABLE_PREVIEW_FEATURES
#endif
#include <msquic.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <optional>
#include <random>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

constexpr uint8_t kProtocolVersion = 2;
constexpr uint32_t kFrameHeaderBytes = 16;
constexpr uint32_t kApplicationMax = 1024u * 1024u;
constexpr uint32_t kMaxReceiveBytes = 16u * 1024u * 1024u;
constexpr uint32_t kSecretBytes = 32;
constexpr uint32_t kNonceBytes = 32;
constexpr uint32_t kCertificatePinBytes = 32;
constexpr uint32_t kExporterBytes = 32;
constexpr uint32_t kMaxReadBytes = 4u * 1024u * 1024u;
constexpr char kAlpn[] = "avaca-remote/2";
constexpr char kExporterLabel[] = "EXPORTER-AVACA-REMOTE-V2";
constexpr char kPlaybackDomain[] = "AVACA-REMOTE-V2/PLAYBACK";
constexpr char kPreAuthContext[] = "AVACA-REMOTE/PREAUTH/V2";

// The Android adapter uses a small self-contained SHA-256 implementation so
// the bridge does not import a second OpenSSL ABI alongside MsQuic/quictls.
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

std::vector<uint8_t> HmacSha256(const std::vector<uint8_t>& key,
                                const std::vector<uint8_t>& message) {
  std::array<uint8_t, 64> padded{};
  if (key.size() > padded.size()) {
    Sha256 hash;
    Sha256Update(&hash, key.data(), key.size());
    const auto digest = Sha256Finish(&hash);
    std::copy(digest.begin(), digest.end(), padded.begin());
  } else {
    std::copy(key.begin(), key.end(), padded.begin());
  }
  std::array<uint8_t, 64> inner{};
  std::array<uint8_t, 64> outer{};
  for (size_t index = 0; index < padded.size(); ++index) {
    inner[index] = padded[index] ^ 0x36;
    outer[index] = padded[index] ^ 0x5c;
  }
  Sha256 inner_hash;
  Sha256Update(&inner_hash, inner.data(), inner.size());
  Sha256Update(&inner_hash, message.data(), message.size());
  const auto inner_digest = Sha256Finish(&inner_hash);
  Sha256 outer_hash;
  Sha256Update(&outer_hash, outer.data(), outer.size());
  Sha256Update(&outer_hash, inner_digest.data(), inner_digest.size());
  const auto digest = Sha256Finish(&outer_hash);
  return std::vector<uint8_t>(digest.begin(), digest.end());
}

bool ConstantTimeEquals(const std::vector<uint8_t>& left,
                        const std::vector<uint8_t>& right) {
  if (left.size() != right.size()) return false;
  uint8_t difference = 0;
  for (size_t index = 0; index < left.size(); ++index) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

std::vector<uint8_t> Sha256Bytes(const uint8_t* bytes, size_t length) {
  Sha256 hash;
  Sha256Update(&hash, bytes, length);
  const auto digest = Sha256Finish(&hash);
  return std::vector<uint8_t>(digest.begin(), digest.end());
}

void Wipe(std::vector<uint8_t>* bytes) {
  if (bytes == nullptr) return;
  std::fill(bytes->begin(), bytes->end(), 0);
  bytes->clear();
}

void AppendUint16(std::vector<uint8_t>* output, uint16_t value) {
  output->push_back(static_cast<uint8_t>(value >> 8));
  output->push_back(static_cast<uint8_t>(value));
}

void AppendUint64(std::vector<uint8_t>* output, uint64_t value) {
  for (int index = 7; index >= 0; --index) {
    output->push_back(static_cast<uint8_t>(value >> (index * 8)));
  }
}

void AppendField(std::vector<uint8_t>* output, const std::string& value) {
  if (value.size() > 0xffff) return;
  AppendUint16(output, static_cast<uint16_t>(value.size()));
  output->insert(output->end(), value.begin(), value.end());
}

void AppendField(std::vector<uint8_t>* output,
                 const std::vector<uint8_t>& value) {
  if (value.size() > 0xffff) return;
  AppendUint16(output, static_cast<uint16_t>(value.size()));
  output->insert(output->end(), value.begin(), value.end());
}

std::vector<uint8_t> BuildTranscript(
    const char* label,
    const std::string& domain,
    const std::vector<uint8_t>& binding,
    const std::vector<std::vector<uint8_t>>& fields) {
  std::vector<uint8_t> transcript(
      reinterpret_cast<const uint8_t*>(kPreAuthContext),
      reinterpret_cast<const uint8_t*>(kPreAuthContext) +
          std::strlen(kPreAuthContext));
  transcript.push_back(0);
  AppendField(&transcript, std::string(label));
  AppendField(&transcript, domain);
  AppendField(&transcript, binding);
  for (const auto& field : fields) AppendField(&transcript, field);
  return transcript;
}

std::string Base64UrlEncode(const std::vector<uint8_t>& bytes) {
  constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  std::string result;
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
  for (const auto character : value) {
    int digit = -1;
    if (character >= 'A' && character <= 'Z') digit = character - 'A';
    if (character >= 'a' && character <= 'z') digit = character - 'a' + 26;
    if (character >= '0' && character <= '9') digit = character - '0' + 52;
    if (character == '-') digit = 62;
    if (character == '_') digit = 63;
    if (digit < 0) return std::nullopt;
    accumulator = (accumulator << 6) | static_cast<uint32_t>(digit);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      result.push_back(static_cast<uint8_t>((accumulator >> bits) & 0xff));
    }
  }
  if (bits >= 6 ||
      (bits > 0 && (accumulator & ((1u << bits) - 1u)) != 0)) {
    return std::nullopt;
  }
  return result;
}

std::string JsonQuote(const std::string& value) {
  std::string result = "\"";
  for (const auto character : value) {
    if (character == '\"') result += "\\\"";
    else if (character == '\\') result += "\\\\";
    else if (static_cast<unsigned char>(character) < 0x20) return {};
    else result.push_back(character);
  }
  result.push_back('\"');
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
  size_t index = start + prefix.size();
  if (index == json.size() || json[index] < '0' || json[index] > '9') {
    return std::nullopt;
  }
  uint64_t value = 0;
  while (index < json.size() && json[index] >= '0' && json[index] <= '9') {
    const auto digit = static_cast<uint64_t>(json[index++] - '0');
    if (value > (UINT64_MAX - digit) / 10) return std::nullopt;
    value = value * 10 + digit;
  }
  return value;
}

std::optional<std::vector<uint8_t>> JsonBytes(const std::string& json,
                                              const char* key) {
  const auto encoded = JsonString(json, key);
  if (!encoded) return std::nullopt;
  return Base64UrlDecode(*encoded);
}

std::vector<uint8_t> BuildFrame(uint8_t opcode,
                                uint64_t request_id,
                                const std::string& payload) {
  std::vector<uint8_t> frame(kFrameHeaderBytes + payload.size(), 0);
  frame[0] = kProtocolVersion;
  frame[1] = opcode;
  frame[4] = static_cast<uint8_t>(payload.size() >> 24);
  frame[5] = static_cast<uint8_t>(payload.size() >> 16);
  frame[6] = static_cast<uint8_t>(payload.size() >> 8);
  frame[7] = static_cast<uint8_t>(payload.size());
  for (int index = 0; index < 8; ++index) {
    frame[8 + index] =
        static_cast<uint8_t>(request_id >> ((7 - index) * 8));
  }
  std::memcpy(frame.data() + kFrameHeaderBytes, payload.data(), payload.size());
  return frame;
}

struct PendingSend {
  std::vector<uint8_t> bytes;
  QUIC_BUFFER buffer{};
};

class RemotePlayback final : public std::enable_shared_from_this<RemotePlayback> {
  class ActiveReadGuard final {
   public:
    explicit ActiveReadGuard(RemotePlayback* owner) : owner_(owner) {}
    ~ActiveReadGuard() {
      if (owner_ != nullptr) owner_->EndReadCall();
    }

   private:
    RemotePlayback* owner_;
  };

  class CallbackGuard final {
   public:
    explicit CallbackGuard(RemotePlayback* owner) : owner_(owner) {
      owner_->BeginCallback();
    }
    ~CallbackGuard() { owner_->EndCallback(); }

   private:
    RemotePlayback* owner_;
  };

 public:
  RemotePlayback(std::string server_id,
                 std::string client_id,
                 std::string host,
                 uint16_t port,
                 std::vector<uint8_t> pin,
                 std::vector<uint8_t> secret,
                 std::string session_id,
                 std::string resource_id,
                 std::vector<uint8_t> grant,
                 uint64_t resource_length)
      : server_id_(std::move(server_id)),
        client_id_(std::move(client_id)),
        host_(std::move(host)),
        port_(port),
        pin_(std::move(pin)),
        secret_(std::move(secret)),
        session_id_(std::move(session_id)),
        resource_id_(std::move(resource_id)),
        grant_(std::move(grant)),
        resource_length_(resource_length) {}

  ~RemotePlayback() { Close(); }

  int Start() {
    QUIC_STATUS status = MsQuicOpen2(&api_);
    if (QUIC_FAILED(status) || api_ == nullptr) return status;
    QUIC_REGISTRATION_CONFIG registration_config{};
    registration_config.AppName = "avaca-player-android";
    registration_config.ExecutionProfile = QUIC_EXECUTION_PROFILE_LOW_LATENCY;
    status = api_->RegistrationOpen(&registration_config, &registration_);
    if (QUIC_FAILED(status)) return status;
    QUIC_BUFFER alpn{static_cast<uint32_t>(sizeof(kAlpn) - 1),
                     reinterpret_cast<uint8_t*>(const_cast<char*>(kAlpn))};
    QUIC_SETTINGS settings{};
    settings.IsSet.IdleTimeoutMs = TRUE;
    settings.IdleTimeoutMs = 60000;
    settings.IsSet.PeerBidiStreamCount = TRUE;
    settings.PeerBidiStreamCount = 1;
    status = api_->ConfigurationOpen(registration_, &alpn, 1, &settings,
                                     sizeof(settings), nullptr,
                                     &configuration_);
    if (QUIC_FAILED(status)) return status;
    QUIC_CREDENTIAL_CONFIG credentials{};
    credentials.Type = QUIC_CREDENTIAL_TYPE_NONE;
    credentials.Flags = static_cast<QUIC_CREDENTIAL_FLAGS>(
        QUIC_CREDENTIAL_FLAG_CLIENT |
        QUIC_CREDENTIAL_FLAG_INDICATE_CERTIFICATE_RECEIVED |
        QUIC_CREDENTIAL_FLAG_DEFER_CERTIFICATE_VALIDATION |
        QUIC_CREDENTIAL_FLAG_USE_PORTABLE_CERTIFICATES);
    status = api_->ConfigurationLoadCredential(configuration_, &credentials);
    if (QUIC_FAILED(status)) return status;
    status = api_->ConnectionOpen(registration_, &ConnectionCallback, this,
                                  &connection_);
    if (QUIC_FAILED(status)) return status;
    status = api_->ConnectionStart(connection_, configuration_,
                                    QUIC_ADDRESS_FAMILY_UNSPEC, host_.c_str(),
                                    port_);
    if (QUIC_FAILED(status)) return status;
    connection_start_succeeded_ = true;
    return QUIC_STATUS_SUCCESS;
  }

  bool WaitAuthenticated() {
    std::unique_lock<std::mutex> lock(mutex_);
    return condition_.wait_for(lock, std::chrono::seconds(15), [this] {
      return authenticated_ || failure_status_ != QUIC_STATUS_SUCCESS || closed_;
    }) && authenticated_ && failure_status_ == QUIC_STATUS_SUCCESS;
  }

  bool OpenResource() {
    const std::string payload =
        std::string("{\"playbackSessionId\":") + JsonQuote(session_id_) +
        ",\"resourceId\":" + JsonQuote(resource_id_) +
        ",\"playbackGrant\":" + JsonQuote(Base64UrlEncode(grant_)) + "}";
    if (!SendFrame(0x40, 3, payload)) return false;
    std::unique_lock<std::mutex> lock(mutex_);
    return condition_.wait_for(lock, std::chrono::seconds(15), [this] {
      return open_complete_ || failure_status_ != QUIC_STATUS_SUCCESS || closed_;
    }) && open_complete_ && failure_status_ == QUIC_STATUS_SUCCESS;
  }

  int Read(uint64_t offset, uint8_t* destination, uint32_t length) {
    if (destination == nullptr && length != 0) return -1;
    if (length > kMaxReadBytes || offset > resource_length_ ||
        length > resource_length_ - offset) {
      return -1;
    }
    uint64_t request_id = 0;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (close_started_ || closing_ || failure_status_ != QUIC_STATUS_SUCCESS ||
          !open_complete_ || read_in_flight_) {
        return -1;
      }
      ++active_read_calls_;
      read_in_flight_ = true;
      read_cancelled_ = false;
      active_request_id_ = ++next_request_id_;
      active_offset_ = offset;
      active_length_ = length;
      read_bytes_.clear();
      request_id = active_request_id_;
    }
    ActiveReadGuard read_guard(this);
    const std::string payload =
        std::string("{\"resourceHandle\":") + JsonQuote(resource_handle_) +
        ",\"offset\":" + std::to_string(offset) +
        ",\"length\":" + std::to_string(length) + "}";
    if (!SendFrame(0x42, request_id, payload)) {
      std::lock_guard<std::mutex> lock(mutex_);
      read_in_flight_ = false;
      return -1;
    }
    std::unique_lock<std::mutex> lock(mutex_);
    condition_.wait_for(lock, std::chrono::seconds(30), [this] {
      return !read_in_flight_ || failure_status_ != QUIC_STATUS_SUCCESS ||
             closed_;
    });
    if (read_in_flight_) {
      read_in_flight_ = false;
      return -1;
    }
    if (read_cancelled_ || failure_status_ != QUIC_STATUS_SUCCESS || closed_) {
      return -2;
    }
    if (read_bytes_.size() > length) return -1;
    std::copy(read_bytes_.begin(), read_bytes_.end(), destination);
    return static_cast<int>(read_bytes_.size());
  }

  bool Cancel() {
    uint64_t request_id = 0;
    uint64_t cancel_request_id = 0;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (close_started_ || !read_in_flight_) return false;
      read_cancelled_ = true;
      request_id = active_request_id_;
      cancel_request_id = ++next_request_id_;
      read_in_flight_ = false;
      condition_.notify_all();
    }
    const auto payload = std::string("{\"targetRequestId\":") +
                         std::to_string(request_id) + "}";
    return SendFrame(0x44, cancel_request_id, payload);
  }

  void Close() {
    HQUIC connection = nullptr;
    std::string resource_handle;
    uint64_t close_request_id = 0;
    bool connection_start_succeeded = false;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      if (close_complete_) return;
      if (close_started_) {
        condition_.wait(lock, [this]() { return close_complete_; });
        return;
      }
      close_started_ = true;
      read_cancelled_ = true;
      read_in_flight_ = false;
      condition_.notify_all();
      condition_.wait(lock, [this]() { return active_read_calls_ == 0; });
      connection = connection_;
      connection_start_succeeded = connection_start_succeeded_;
      if (!closed_ && open_complete_ && !resource_handle_.empty()) {
        resource_handle = resource_handle_;
        close_request_id = next_request_id_++;
      }
    }
    // Release the server-side file handle before tearing down the QUIC
    // connection.  This mirrors the Windows native bridge and keeps the
    // authenticated range session's lease explicit on Android as well.
    if (connection != nullptr && !resource_handle.empty()) {
      const auto payload = std::string("{\"resourceHandle\":") +
                           JsonQuote(resource_handle) + "}";
      if (SendFrame(0x45, close_request_id, payload)) {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait_for(lock, std::chrono::seconds(5), [this]() {
          return pending_sends_.empty() || closed_;
        });
      }
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      closing_ = true;
      connection = connection_;
      condition_.notify_all();
    }
    if (connection != nullptr && api_ != nullptr &&
        connection_start_succeeded) {
      api_->ConnectionShutdown(connection, QUIC_CONNECTION_SHUTDOWN_FLAG_SILENT,
                               0);
    } else if (connection != nullptr && api_ != nullptr) {
      api_->ConnectionClose(connection);
      std::lock_guard<std::mutex> lock(mutex_);
      if (connection_ == connection) connection_ = nullptr;
      closed_ = true;
      condition_.notify_all();
    }
    {
      std::unique_lock<std::mutex> lock(mutex_);
      condition_.wait(lock, [this] {
        return closed_ || connection_ == nullptr;
      });
    }
    if (api_ != nullptr) {
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait(lock, [this]() { return active_callbacks_ == 0; });
      }
      HQUIC stream = nullptr;
      HQUIC remaining_connection = nullptr;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        stream = stream_;
        remaining_connection = connection_;
      }
      if (stream != nullptr) {
        api_->StreamClose(stream);
        std::lock_guard<std::mutex> lock(mutex_);
        if (stream_ == stream) stream_ = nullptr;
      }
      if (remaining_connection != nullptr) {
        api_->ConnectionClose(remaining_connection);
        std::lock_guard<std::mutex> lock(mutex_);
        if (connection_ == remaining_connection) connection_ = nullptr;
      }
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait(lock, [this]() { return active_callbacks_ == 0; });
      }
      if (configuration_ != nullptr) api_->ConfigurationClose(configuration_);
      configuration_ = nullptr;
      if (registration_ != nullptr) api_->RegistrationClose(registration_);
      registration_ = nullptr;
      MsQuicClose(api_);
      api_ = nullptr;
    }
    {
      std::unique_lock<std::mutex> lock(mutex_);
      closed_ = true;
      condition_.wait(lock, [this]() { return active_callbacks_ == 0; });
      for (auto* pending : pending_sends_) delete pending;
      pending_sends_.clear();
      close_complete_ = true;
      condition_.notify_all();
    }
    Wipe(&secret_);
    Wipe(&pin_);
    Wipe(&grant_);
  }

 private:
  static QUIC_STATUS QUIC_API ConnectionCallback(HQUIC connection,
                                                  void* context,
                                                  QUIC_CONNECTION_EVENT* event) {
    auto* self = static_cast<RemotePlayback*>(context);
    if (self == nullptr) return QUIC_STATUS_INVALID_PARAMETER;
    CallbackGuard callback_guard(self);
    if (event->Type == QUIC_CONNECTION_EVENT_CONNECTED) {
      self->OnConnected(connection);
    } else if (event->Type == QUIC_CONNECTION_EVENT_PEER_CERTIFICATE_RECEIVED) {
      self->OnCertificate(connection, event);
      return QUIC_STATUS_PENDING;
    } else if (event->Type == QUIC_CONNECTION_EVENT_SHUTDOWN_INITIATED_BY_TRANSPORT) {
      self->Fail(event->SHUTDOWN_INITIATED_BY_TRANSPORT.Status);
    } else if (event->Type == QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE) {
      {
        std::lock_guard<std::mutex> lock(self->mutex_);
        self->closed_ = true;
        self->failure_status_ = self->failure_status_ == QUIC_STATUS_SUCCESS
                                    ? QUIC_STATUS_ABORTED
                                    : self->failure_status_;
        self->condition_.notify_all();
      }
      if (self->api_ != nullptr) {
        self->api_->ConnectionClose(connection);
        std::lock_guard<std::mutex> lock(self->mutex_);
        if (self->connection_ == connection) self->connection_ = nullptr;
      }
    }
    return QUIC_STATUS_SUCCESS;
  }

  static QUIC_STATUS QUIC_API StreamCallback(HQUIC stream,
                                              void* context,
                                              QUIC_STREAM_EVENT* event) {
    auto* self = static_cast<RemotePlayback*>(context);
    if (self == nullptr) return QUIC_STATUS_INVALID_PARAMETER;
    CallbackGuard callback_guard(self);
    if (event->Type == QUIC_STREAM_EVENT_RECEIVE) {
      std::vector<uint8_t> bytes;
      if (event->RECEIVE.TotalBufferLength > kMaxReceiveBytes) {
        self->Fail(QUIC_STATUS_OUT_OF_MEMORY);
        return QUIC_STATUS_SUCCESS;
      }
      bytes.reserve(static_cast<size_t>(event->RECEIVE.TotalBufferLength));
      for (uint32_t index = 0; index < event->RECEIVE.BufferCount; ++index) {
        const auto& buffer = event->RECEIVE.Buffers[index];
        bytes.insert(bytes.end(), buffer.Buffer, buffer.Buffer + buffer.Length);
      }
      self->ProcessBytes(bytes);
    } else if (event->Type == QUIC_STREAM_EVENT_SEND_COMPLETE) {
      auto* pending = static_cast<PendingSend*>(event->SEND_COMPLETE.ClientContext);
      if (pending != nullptr) self->RetireSend(pending);
    } else if (event->Type == QUIC_STREAM_EVENT_PEER_SEND_ABORTED ||
               event->Type == QUIC_STREAM_EVENT_PEER_RECEIVE_ABORTED) {
      self->Fail(QUIC_STATUS_ABORTED);
    } else if (event->Type == QUIC_STREAM_EVENT_SHUTDOWN_COMPLETE) {
      if (self->api_ != nullptr) {
        self->api_->StreamClose(stream);
        std::lock_guard<std::mutex> lock(self->mutex_);
        if (self->stream_ == stream) self->stream_ = nullptr;
      }
    }
    return QUIC_STATUS_SUCCESS;
  }

  void OnCertificate(HQUIC connection, QUIC_CONNECTION_EVENT* event) {
    const auto* portable = reinterpret_cast<const QUIC_BUFFER*>(
        event->PEER_CERTIFICATE_RECEIVED.Certificate);
    bool accepted = portable != nullptr && portable->Buffer != nullptr &&
                    portable->Length != 0;
    if (accepted) {
      const auto digest = Sha256Bytes(portable->Buffer, portable->Length);
      const std::vector<uint8_t> pin(pin_.begin(), pin_.end());
      accepted = ConstantTimeEquals(digest, pin);
    }
    api_->ConnectionCertificateValidationComplete(
        connection, accepted ? TRUE : FALSE,
        accepted ? QUIC_TLS_ALERT_CODE_SUCCESS
                 : QUIC_TLS_ALERT_CODE_BAD_CERTIFICATE);
    if (!accepted) Fail(QUIC_STATUS_BAD_CERTIFICATE);
  }

  void OnConnected(HQUIC connection) {
    std::vector<uint8_t> binding(kExporterBytes);
    QUIC_KEYING_MATERIAL_CONFIG exporter{};
    exporter.Label = kExporterLabel;
    exporter.OutputLength = kExporterBytes;
    if (QUIC_FAILED(api_->ConnectionExportKeyingMaterial(
            connection, &exporter, binding.data()))) {
      Fail(QUIC_STATUS_ABORTED);
      return;
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      channel_binding_ = binding;
      connected_ = true;
    }
    HQUIC stream = nullptr;
    if (QUIC_FAILED(api_->StreamOpen(connection, QUIC_STREAM_OPEN_FLAG_NONE,
                                     &StreamCallback, this, &stream)) ||
        QUIC_FAILED(api_->StreamStart(stream, QUIC_STREAM_START_FLAG_IMMEDIATE))) {
      if (stream != nullptr) api_->StreamClose(stream);
      Fail(QUIC_STATUS_ABORTED);
      return;
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stream_ = stream;
    }
    client_nonce_.resize(kNonceBytes);
    std::random_device random;
    for (auto& value : client_nonce_) value = static_cast<uint8_t>(random());
    const auto transcript = BuildTranscript(
        "client-hello", kPlaybackDomain, channel_binding_,
        {std::vector<uint8_t>(client_id_.begin(), client_id_.end()),
         client_nonce_});
    const auto proof = HmacSha256(secret_, transcript);
    const auto payload = std::string("{\"clientId\":") +
                         JsonQuote(client_id_) + ",\"clientNonce\":" +
                         JsonQuote(Base64UrlEncode(client_nonce_)) +
                         ",\"proof\":" + JsonQuote(Base64UrlEncode(proof)) +
                         "}";
    if (!SendFrame(0x01, 1, payload)) Fail(QUIC_STATUS_ABORTED);
  }

  void ProcessBytes(const std::vector<uint8_t>& bytes) {
    std::vector<std::vector<uint8_t>> frames;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      receive_buffer_.insert(receive_buffer_.end(), bytes.begin(), bytes.end());
      if (receive_buffer_.size() > kMaxReceiveBytes) {
        failure_status_ = QUIC_STATUS_OUT_OF_MEMORY;
        condition_.notify_all();
        return;
      }
      while (receive_buffer_.size() >= kFrameHeaderBytes) {
        if (receive_buffer_[0] != kProtocolVersion || receive_buffer_[2] != 0 ||
            receive_buffer_[3] != 0) {
          failure_status_ = QUIC_STATUS_INVALID_PARAMETER;
          condition_.notify_all();
          return;
        }
        const auto length = (static_cast<uint32_t>(receive_buffer_[4]) << 24) |
                            (static_cast<uint32_t>(receive_buffer_[5]) << 16) |
                            (static_cast<uint32_t>(receive_buffer_[6]) << 8) |
                            receive_buffer_[7];
        if (length > kApplicationMax) {
          failure_status_ = QUIC_STATUS_OUT_OF_MEMORY;
          condition_.notify_all();
          return;
        }
        if (receive_buffer_.size() < kFrameHeaderBytes + length) break;
        frames.emplace_back(receive_buffer_.begin(),
                            receive_buffer_.begin() + kFrameHeaderBytes + length);
        receive_buffer_.erase(receive_buffer_.begin(),
                              receive_buffer_.begin() + kFrameHeaderBytes + length);
      }
    }
    for (const auto& frame : frames) {
      uint64_t request_id = 0;
      for (size_t index = 0; index < 8; ++index) {
        request_id = (request_id << 8) | frame[8 + index];
      }
      HandleFrame(frame[1], request_id,
                  std::string(reinterpret_cast<const char*>(frame.data() + 16),
                              frame.size() - 16));
    }
  }

  void HandleFrame(uint8_t opcode, uint64_t request_id, const std::string& payload) {
    if (opcode == 0x02) {
      const auto server_id = JsonString(payload, "serverId");
      const auto client_id = JsonString(payload, "clientId");
      const auto server_nonce = JsonBytes(payload, "serverNonce");
      const auto proof = JsonBytes(payload, "proof");
      if (!server_id || !client_id || !server_nonce || !proof ||
          *server_id != server_id_ || *client_id != client_id_ ||
          server_nonce->size() != kNonceBytes || proof->size() != kSecretBytes) {
        Fail(QUIC_STATUS_BAD_CERTIFICATE);
        return;
      }
      {
        std::lock_guard<std::mutex> lock(mutex_);
        server_nonce_ = *server_nonce;
      }
      const auto transcript = BuildTranscript(
          "server-hello", kPlaybackDomain, channel_binding_,
          {std::vector<uint8_t>(server_id->begin(), server_id->end()),
           std::vector<uint8_t>(client_id_.begin(), client_id_.end()),
           client_nonce_, *server_nonce});
      if (!ConstantTimeEquals(HmacSha256(secret_, transcript), *proof)) {
        Fail(QUIC_STATUS_BAD_CERTIFICATE);
        return;
      }
      const auto acceptance_transcript = BuildTranscript(
          "authenticated", kPlaybackDomain, channel_binding_,
          {std::vector<uint8_t>(server_id_.begin(), server_id_.end()),
           std::vector<uint8_t>(client_id_.begin(), client_id_.end()),
           client_nonce_, *server_nonce});
      const auto acceptance = HmacSha256(secret_, acceptance_transcript);
      const auto acceptance_payload = std::string("{\"serverId\":") +
          JsonQuote(server_id_) + ",\"clientId\":" + JsonQuote(client_id_) +
          ",\"proof\":" + JsonQuote(Base64UrlEncode(acceptance)) + "}";
      if (!SendFrame(0x03, 2, acceptance_payload)) Fail(QUIC_STATUS_ABORTED);
      return;
    }
    if (opcode == 0x05) {
      const auto server_id = JsonString(payload, "serverId");
      const auto client_id = JsonString(payload, "clientId");
      const auto proof = JsonBytes(payload, "proof");
      if (!server_id || !client_id || !proof || *server_id != server_id_ ||
          *client_id != client_id_ || proof->size() != kSecretBytes) {
        Fail(QUIC_STATUS_BAD_CERTIFICATE);
        return;
      }
      const auto transcript = BuildTranscript(
          "authenticated", kPlaybackDomain, channel_binding_,
          {std::vector<uint8_t>(server_id_.begin(), server_id_.end()),
           std::vector<uint8_t>(client_id_.begin(), client_id_.end()),
           client_nonce_, server_nonce_});
      if (!ConstantTimeEquals(HmacSha256(secret_, transcript), *proof)) {
        Fail(QUIC_STATUS_BAD_CERTIFICATE);
        return;
      }
      std::lock_guard<std::mutex> lock(mutex_);
      authenticated_ = true;
      condition_.notify_all();
      return;
    }
    if (opcode == 0x41 && request_id == 3) {
      const auto handle = JsonString(payload, "resourceHandle");
      const auto length = JsonUint64(payload, "contentLength");
      if (!handle || handle->empty() || !length) {
        Fail(QUIC_STATUS_INVALID_PARAMETER);
        return;
      }
      std::lock_guard<std::mutex> lock(mutex_);
      resource_handle_ = *handle;
      resource_length_ = *length;
      open_complete_ = true;
      condition_.notify_all();
      return;
    }
    if (opcode == 0x43) {
      const auto offset = JsonUint64(payload, "offset");
      const auto bytes = JsonBytes(payload, "bytes");
      std::lock_guard<std::mutex> lock(mutex_);
      if (!offset || !bytes || read_cancelled_ || !read_in_flight_ ||
          request_id != active_request_id_ || *offset != active_offset_ ||
          bytes->size() > active_length_) {
        if (read_cancelled_) return;
        failure_status_ = QUIC_STATUS_INVALID_STATE;
        condition_.notify_all();
        return;
      }
      read_bytes_ = *bytes;
      read_in_flight_ = false;
      condition_.notify_all();
      return;
    }
    if (opcode == 0x7f) {
      const auto failure_code = JsonString(payload, "failureCode");
      std::lock_guard<std::mutex> lock(mutex_);
      if (failure_code && *failure_code == "cancelled" &&
          request_id == active_request_id_) {
        read_cancelled_ = true;
        read_in_flight_ = false;
      } else {
        failure_status_ = QUIC_STATUS_ABORTED;
        read_in_flight_ = false;
      }
      condition_.notify_all();
    }
  }

  bool SendFrame(uint8_t opcode, uint64_t request_id, const std::string& payload) {
    if (payload.size() > kApplicationMax) return false;
    std::unique_ptr<PendingSend> pending(new (std::nothrow) PendingSend());
    if (!pending) return false;
    pending->bytes = BuildFrame(opcode, request_id, payload);
    pending->buffer.Length = static_cast<uint32_t>(pending->bytes.size());
    pending->buffer.Buffer = pending->bytes.data();
    auto* raw = pending.release();
    HQUIC stream = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (closing_ || stream_ == nullptr) {
        delete raw;
        return false;
      }
      stream = stream_;
      pending_sends_.insert(raw);
    }
    const auto status = api_->StreamSend(stream, &raw->buffer, 1,
                                         QUIC_SEND_FLAG_NONE, raw);
    if (QUIC_FAILED(status)) {
      RetireSend(raw);
      Fail(status);
      return false;
    }
    return true;
  }

  void RetireSend(PendingSend* pending) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (pending_sends_.erase(pending) != 0) delete pending;
    condition_.notify_all();
  }

  void EndReadCall() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (active_read_calls_ != 0) --active_read_calls_;
    condition_.notify_all();
  }

  void BeginCallback() {
    std::lock_guard<std::mutex> lock(mutex_);
    ++active_callbacks_;
  }

  void EndCallback() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (active_callbacks_ != 0) --active_callbacks_;
    condition_.notify_all();
  }

  void Fail(int32_t status) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (failure_status_ == QUIC_STATUS_SUCCESS) failure_status_ = status;
    condition_.notify_all();
  }

  const std::string server_id_;
  const std::string client_id_;
  const std::string host_;
  const uint16_t port_;
  std::vector<uint8_t> pin_;
  std::vector<uint8_t> secret_;
  const std::string session_id_;
  const std::string resource_id_;
  std::vector<uint8_t> grant_;
  uint64_t resource_length_;

  const QUIC_API_TABLE* api_ = nullptr;
  HQUIC registration_ = nullptr;
  HQUIC configuration_ = nullptr;
  HQUIC connection_ = nullptr;
  HQUIC stream_ = nullptr;
  std::set<PendingSend*> pending_sends_;

  std::mutex mutex_;
  std::condition_variable condition_;
  bool connected_ = false;
  bool authenticated_ = false;
  bool open_complete_ = false;
  bool closed_ = false;
  bool connection_start_succeeded_ = false;
  bool close_started_ = false;
  bool close_complete_ = false;
  bool closing_ = false;
  uint32_t active_read_calls_ = 0;
  uint32_t active_callbacks_ = 0;
  int32_t failure_status_ = QUIC_STATUS_SUCCESS;
  uint64_t next_request_id_ = 3;
  uint64_t active_request_id_ = 0;
  uint64_t active_offset_ = 0;
  uint32_t active_length_ = 0;
  bool read_in_flight_ = false;
  bool read_cancelled_ = false;
  std::vector<uint8_t> read_bytes_;
  std::vector<uint8_t> receive_buffer_;
  std::vector<uint8_t> channel_binding_;
  std::vector<uint8_t> client_nonce_;
  std::vector<uint8_t> server_nonce_;
  std::string resource_handle_;
};

std::mutex g_handles_mutex;
std::unordered_map<jlong, std::shared_ptr<RemotePlayback>> g_handles;
jlong g_next_handle = 1;

std::optional<std::string> JString(JNIEnv* env, jstring value) {
  if (env == nullptr || value == nullptr) return std::nullopt;
  const auto* chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) return std::nullopt;
  std::string result(chars);
  env->ReleaseStringUTFChars(value, chars);
  return result;
}

std::optional<std::vector<uint8_t>> JBytes(JNIEnv* env, jbyteArray value) {
  if (env == nullptr || value == nullptr) return std::nullopt;
  const auto length = env->GetArrayLength(value);
  if (length < 0 || length > static_cast<jsize>(kApplicationMax)) {
    return std::nullopt;
  }
  std::vector<uint8_t> result(static_cast<size_t>(length));
  if (length != 0) {
    env->GetByteArrayRegion(value, 0, length,
                            reinterpret_cast<jbyte*>(result.data()));
    if (env->ExceptionCheck()) return std::nullopt;
  }
  return result;
}

std::shared_ptr<RemotePlayback> FindHandle(jlong handle) {
  std::lock_guard<std::mutex> lock(g_handles_mutex);
  const auto found = g_handles.find(handle);
  return found == g_handles.end() ? nullptr : found->second;
}

bool IsSafeIdentifier(const std::string& value) {
  if (value.empty() || value.size() > 256) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char character) {
    return (character >= 'A' && character <= 'Z') ||
           (character >= 'a' && character <= 'z') ||
           (character >= '0' && character <= '9') || character == '.' ||
           character == '_' || character == '~' || character == '-';
  });
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_avaca_player_avaca_NativeRemoteQuic_nativeOpen(
    JNIEnv* env,
    jclass,
    jstring server_id,
    jstring client_id,
    jstring host,
    jint port,
    jbyteArray pin,
    jbyteArray secret,
    jstring session_id,
    jstring resource_id,
    jbyteArray grant,
    jlong resource_length) {
  const auto server = JString(env, server_id);
  const auto client = JString(env, client_id);
  const auto endpoint = JString(env, host);
  const auto session = JString(env, session_id);
  const auto resource = JString(env, resource_id);
  const auto pin_bytes = JBytes(env, pin);
  const auto secret_bytes = JBytes(env, secret);
  const auto grant_bytes = JBytes(env, grant);
  if (!server || !client || !endpoint || !session || !resource || !pin_bytes ||
      !secret_bytes || !grant_bytes || !IsSafeIdentifier(*server) ||
      !IsSafeIdentifier(*client) || !IsSafeIdentifier(*session) ||
      resource->empty() || resource->size() > 256 || port < 1 || port > 65535 ||
      pin_bytes->size() != kCertificatePinBytes ||
      secret_bytes->size() != kSecretBytes || grant_bytes->size() != kSecretBytes ||
      resource_length < 0) {
    return 0;
  }
  auto playback = std::make_shared<RemotePlayback>(
      *server, *client, *endpoint, static_cast<uint16_t>(port), *pin_bytes,
      *secret_bytes, *session, *resource, *grant_bytes,
      static_cast<uint64_t>(resource_length));
  if (QUIC_FAILED(playback->Start()) || !playback->WaitAuthenticated() ||
      !playback->OpenResource()) {
    playback->Close();
    return 0;
  }
  std::lock_guard<std::mutex> lock(g_handles_mutex);
  const auto handle = g_next_handle++;
  g_handles.emplace(handle, std::move(playback));
  return handle;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_avaca_player_avaca_NativeRemoteQuic_nativeRead(
    JNIEnv* env,
    jclass,
    jlong handle,
    jlong offset,
    jbyteArray destination,
    jint destination_offset,
    jint length) {
  if (offset < 0 || destination_offset < 0 || length < 0 ||
      length > static_cast<jint>(kMaxReadBytes) ||
      destination == nullptr ||
      destination_offset > env->GetArrayLength(destination) - length) {
    return -1;
  }
  const auto playback = FindHandle(handle);
  if (!playback) return -1;
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  const auto result = playback->Read(static_cast<uint64_t>(offset), bytes.data(),
                                     static_cast<uint32_t>(length));
  if (result > 0) {
    env->SetByteArrayRegion(destination, destination_offset, result,
                            reinterpret_cast<const jbyte*>(bytes.data()));
    if (env->ExceptionCheck()) return -1;
  }
  return result;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_avaca_player_avaca_NativeRemoteQuic_nativeCancel(
    JNIEnv*, jclass, jlong handle) {
  const auto playback = FindHandle(handle);
  return playback && playback->Cancel() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_avaca_player_avaca_NativeRemoteQuic_nativeClose(
    JNIEnv*, jclass, jlong handle) {
  std::shared_ptr<RemotePlayback> playback;
  {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    const auto found = g_handles.find(handle);
    if (found == g_handles.end()) return;
    playback = std::move(found->second);
    g_handles.erase(found);
  }
  playback->Close();
}

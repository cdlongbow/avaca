#ifndef AVACA_REMOTE_CORE_H_
#define AVACA_REMOTE_CORE_H_

#include <stdint.h>

#ifdef _WIN32
#define AVACA_REMOTE_CORE_API __declspec(dllexport)
#define AVACA_REMOTE_CORE_CALL __cdecl
#else
#define AVACA_REMOTE_CORE_API
#define AVACA_REMOTE_CORE_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (AVACA_REMOTE_CORE_CALL *AvacaRemoteCoreEventCallback)(
    void* context,
    uint64_t object,
    uint32_t event,
    int32_t status,
    uint64_t operation,
    const uint8_t* data,
    uint32_t length,
    uint8_t flags);

AVACA_REMOTE_CORE_API int32_t AVACA_REMOTE_CORE_CALL
avaca_remote_quic_create_server(
    const uint8_t* certificate_sha1_thumbprint,
    uint32_t certificate_sha1_length,
    AvacaRemoteCoreEventCallback callback,
    void* context,
    uint64_t* transport);

AVACA_REMOTE_CORE_API int32_t AVACA_REMOTE_CORE_CALL
avaca_remote_quic_create_client(
    const uint8_t* certificate_sha256_pin,
    uint32_t certificate_sha256_pin_length,
    AvacaRemoteCoreEventCallback callback,
    void* context,
    uint64_t* transport);

typedef struct AvacaRemotePlaybackDescriptor {
  const uint8_t* resource_id;
  uint32_t resource_id_length;
  uint64_t resource_length;
  const char* playback_session_id;
  uint32_t playback_session_id_length;
  const uint8_t* playback_grant;
  uint32_t playback_grant_length;
} AvacaRemotePlaybackDescriptor;

typedef struct AvacaRemoteClientProfile {
  const char* server_id;
  uint32_t server_id_length;
  const char* client_id;
  uint32_t client_id_length;
  const char* host;
  uint32_t host_length;
  uint16_t port;
  const uint8_t* certificate_sha256_pin;
  uint32_t certificate_sha256_pin_length;
  const uint8_t* pairing_secret;
  uint32_t pairing_secret_length;
} AvacaRemoteClientProfile;

typedef int32_t (AVACA_REMOTE_CORE_CALL *AvacaRemotePlaybackReadAt)(
    void* context,
    uint64_t offset,
    uint8_t* destination,
    uint32_t length,
    uint32_t* bytes_read);

AVACA_REMOTE_CORE_API int32_t AVACA_REMOTE_CORE_CALL
avaca_remote_playback_open(
    uint64_t transport,
    const AvacaRemotePlaybackDescriptor* descriptor,
    AvacaRemotePlaybackReadAt read_at,
    void* read_context,
    uint64_t* stream);

/// Production native data-plane entry point.  It creates a fresh authenticated
/// playback QUIC connection and never routes media bytes through Dart.
AVACA_REMOTE_CORE_API int32_t AVACA_REMOTE_CORE_CALL
avaca_remote_playback_open_native(
    const AvacaRemoteClientProfile* profile,
    const AvacaRemotePlaybackDescriptor* descriptor,
    uint64_t* stream);

AVACA_REMOTE_CORE_API int32_t AVACA_REMOTE_CORE_CALL
avaca_remote_playback_read_at(
    uint64_t stream,
    uint64_t offset,
    uint8_t* destination,
    uint32_t length,
    uint32_t* bytes_read);

AVACA_REMOTE_CORE_API int32_t AVACA_REMOTE_CORE_CALL
avaca_remote_playback_cancel(uint64_t stream);

AVACA_REMOTE_CORE_API int32_t AVACA_REMOTE_CORE_CALL
avaca_remote_playback_close(uint64_t stream);

#ifdef __cplusplus
}
#endif

#endif

#ifndef AVACA_REMOTE_QUIC_BRIDGE_H_
#define AVACA_REMOTE_QUIC_BRIDGE_H_

#include <stdint.h>

#ifdef _WIN32
#define AVACA_REMOTE_QUIC_API __declspec(dllexport)
#define AVACA_REMOTE_QUIC_CALL __cdecl
#else
#define AVACA_REMOTE_QUIC_API
#define AVACA_REMOTE_QUIC_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (AVACA_REMOTE_QUIC_CALL *AvacaRemoteQuicEventCallback)(
    void* context,
    uint64_t object,
    uint32_t event,
    int32_t status,
    uint64_t operation,
    const uint8_t* data,
    uint32_t length,
    uint8_t flags);

enum {
  AVACA_REMOTE_QUIC_EVENT_CONNECTED = 1,
  AVACA_REMOTE_QUIC_EVENT_DATA = 2,
  AVACA_REMOTE_QUIC_EVENT_SEND_COMPLETE = 3,
  AVACA_REMOTE_QUIC_EVENT_CLOSED = 4,
  AVACA_REMOTE_QUIC_EVENT_ERROR = 5,
};

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_create(
    const uint8_t* pinned_server_certificate_sha256,
    uint32_t pinned_server_certificate_sha256_length,
    const uint8_t* server_certificate_sha1,
    uint32_t server_certificate_sha1_length,
    AvacaRemoteQuicEventCallback callback,
    void* context,
    uint64_t* transport);

// Role-specific constructors are the production API.  A Server owns only
// its certificate-store identity; an AVACA client owns only its SHA-256 pin.
// Keeping these constructors separate prevents either process from receiving
// the other role's private configuration by accident.  The legacy combined
// constructor above remains only as a source-compatible migration shim.
AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_create_server(
    const uint8_t* server_certificate_sha1,
    uint32_t server_certificate_sha1_length,
    AvacaRemoteQuicEventCallback callback,
    void* context,
    uint64_t* transport);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_create_client(
    const uint8_t* pinned_server_certificate_sha256,
    uint32_t pinned_server_certificate_sha256_length,
    AvacaRemoteQuicEventCallback callback,
    void* context,
    uint64_t* transport);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_listen(
    uint64_t transport,
    uint16_t port,
    uint64_t* listener);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_connect(
    uint64_t transport,
    const char* host,
    uint16_t port,
    uint64_t* connection);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_send(
    uint64_t connection,
    const uint8_t* data,
    uint32_t length,
    uint64_t operation);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_close_connection(uint64_t connection);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_close_listener(uint64_t transport, uint64_t listener);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_close(uint64_t transport);

AVACA_REMOTE_QUIC_API void AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_free_buffer(const uint8_t* data);

AVACA_REMOTE_QUIC_API void AVACA_REMOTE_QUIC_CALL
avaca_remote_quic_ack_receive(
    uint64_t transport,
    uint64_t connection,
    uint32_t length);

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

typedef int32_t (AVACA_REMOTE_QUIC_CALL *AvacaRemotePlaybackReadAt)(
    void* context,
    uint64_t offset,
    uint8_t* destination,
    uint32_t length,
    uint32_t* bytes_read);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_open(
    uint64_t transport,
    const AvacaRemotePlaybackDescriptor* descriptor,
    AvacaRemotePlaybackReadAt read_at,
    void* read_context,
    uint64_t* stream);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_open_native(
    const AvacaRemoteClientProfile* profile,
    const AvacaRemotePlaybackDescriptor* descriptor,
    uint64_t* stream);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_read_at(
    uint64_t stream,
    uint64_t offset,
    uint8_t* destination,
    uint32_t length,
    uint32_t* bytes_read);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_cancel(uint64_t stream);

AVACA_REMOTE_QUIC_API int32_t AVACA_REMOTE_QUIC_CALL
avaca_remote_playback_close(uint64_t stream);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // AVACA_REMOTE_QUIC_BRIDGE_H_

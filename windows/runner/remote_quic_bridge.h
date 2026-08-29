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

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // AVACA_REMOTE_QUIC_BRIDGE_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "../windows/runner/remote_quic_bridge.h"

namespace {

using namespace std::chrono_literals;

struct LoadedBridge {
  HMODULE module = nullptr;
  decltype(&avaca_remote_quic_create) create = nullptr;
  decltype(&avaca_remote_quic_listen) listen = nullptr;
  decltype(&avaca_remote_quic_connect) connect = nullptr;
  decltype(&avaca_remote_quic_send) send = nullptr;
  decltype(&avaca_remote_quic_close_connection) close_connection = nullptr;
  decltype(&avaca_remote_quic_close_listener) close_listener = nullptr;
  decltype(&avaca_remote_quic_close) close = nullptr;
  decltype(&avaca_remote_quic_free_buffer) free_buffer = nullptr;
  decltype(&avaca_remote_quic_ack_receive) ack_receive = nullptr;

  ~LoadedBridge() {
    if (module != nullptr) {
      FreeLibrary(module);
    }
  }

  template <typename Function>
  bool load(Function* target, const char* name) {
    *target = reinterpret_cast<Function>(GetProcAddress(module, name));
    return *target != nullptr;
  }

  bool open(const wchar_t* path) {
    module = LoadLibraryW(path);
    if (module == nullptr) {
      return false;
    }
    return load(&create, "avaca_remote_quic_create") &&
           load(&listen, "avaca_remote_quic_listen") &&
           load(&connect, "avaca_remote_quic_connect") &&
           load(&send, "avaca_remote_quic_send") &&
           load(&close_connection, "avaca_remote_quic_close_connection") &&
           load(&close_listener, "avaca_remote_quic_close_listener") &&
           load(&close, "avaca_remote_quic_close") &&
           load(&free_buffer, "avaca_remote_quic_free_buffer") &&
           load(&ack_receive, "avaca_remote_quic_ack_receive");
  }
};

struct Event {
  uint64_t object = 0;
  uint32_t type = 0;
  int32_t status = 0;
  uint64_t operation = 0;
  uint8_t flags = 0;
  std::vector<uint8_t> data;
};

struct EventSink {
  LoadedBridge* bridge = nullptr;
  uint64_t transport = 0;
  std::mutex mutex;
  std::condition_variable changed;
  std::vector<Event> events;
};

void AVACA_REMOTE_QUIC_CALL OnEvent(
    void* context,
    uint64_t object,
    uint32_t type,
    int32_t status,
    uint64_t operation,
    const uint8_t* data,
    uint32_t length,
    uint8_t flags) {
  auto* sink = static_cast<EventSink*>(context);
  Event event;
  event.object = object;
  event.type = type;
  event.status = status;
  event.operation = operation;
  event.flags = flags;
  if (data != nullptr && length != 0) {
    event.data.assign(data, data + length);
  }
  if (type == AVACA_REMOTE_QUIC_EVENT_DATA && sink->bridge != nullptr) {
    sink->bridge->ack_receive(sink->transport, object, length);
  }
  if (data != nullptr && sink->bridge != nullptr) {
    sink->bridge->free_buffer(data);
  }
  {
    std::lock_guard<std::mutex> lock(sink->mutex);
    sink->events.push_back(std::move(event));
  }
  sink->changed.notify_all();
}

bool WaitForEvent(
    EventSink& sink,
    uint32_t type,
    uint64_t object,
    Event* result,
    std::chrono::milliseconds timeout = 10s) {
  std::unique_lock<std::mutex> lock(sink.mutex);
  const auto predicate = [&]() {
    for (const auto& event : sink.events) {
      if (event.type == type && (object == 0 || event.object == object)) {
        return true;
      }
    }
    return false;
  };
  if (!sink.changed.wait_for(lock, timeout, predicate)) {
    return false;
  }
  for (auto iterator = sink.events.begin(); iterator != sink.events.end();
       ++iterator) {
    if (iterator->type == type && (object == 0 || iterator->object == object)) {
      if (result != nullptr) {
        *result = std::move(*iterator);
      }
      sink.events.erase(iterator);
      return true;
    }
  }
  return false;
}

bool HasEvent(EventSink& sink, uint32_t type, uint64_t object) {
  std::lock_guard<std::mutex> lock(sink.mutex);
  for (const auto& event : sink.events) {
    if (event.type == type && (object == 0 || event.object == object)) {
      return true;
    }
  }
  return false;
}

bool ParseHex(const wchar_t* text, size_t expected_bytes, std::vector<uint8_t>* out) {
  const std::wstring value(text == nullptr ? L"" : text);
  if (value.size() != expected_bytes * 2) {
    return false;
  }
  out->clear();
  out->reserve(expected_bytes);
  for (size_t index = 0; index < value.size(); index += 2) {
    wchar_t* end = nullptr;
    const auto byte = wcstoul(value.substr(index, 2).c_str(), &end, 16);
    if (end == nullptr || *end != L'\0' || byte > 0xff) {
      return false;
    }
    out->push_back(static_cast<uint8_t>(byte));
  }
  return true;
}

std::string Hex(const std::vector<uint8_t>& bytes) {
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (const auto byte : bytes) {
    output << std::setw(2) << static_cast<unsigned int>(byte);
  }
  return output.str();
}

bool Check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
  }
  return condition;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 4) {
    std::wcerr << L"usage: remote_quic_runtime_smoke.exe <bridge.dll> "
                  L"<server-sha1-40-hex> <server-der-sha256-64-hex>"
               << std::endl;
    return 2;
  }

  std::vector<uint8_t> server_sha1;
  std::vector<uint8_t> server_pin;
  if (!ParseHex(argv[2], 20, &server_sha1) ||
      !ParseHex(argv[3], 32, &server_pin)) {
    std::wcerr << L"FAIL: invalid certificate hash argument" << std::endl;
    return 2;
  }

  LoadedBridge bridge;
  if (!Check(bridge.open(argv[1]), "could not load the AVACA MsQuic bridge")) {
    return 1;
  }

  EventSink server_sink{&bridge};
  EventSink client_sink{&bridge};
  EventSink wrong_pin_sink{&bridge};
  uint64_t server_transport = 0;
  uint64_t client_transport = 0;
  uint64_t wrong_pin_transport = 0;
  uint64_t listener = 0;
  uint64_t client_connection = 0;
  uint64_t wrong_pin_connection = 0;
  bool server_closed = false;
  bool client_closed = false;

  const auto create_server = bridge.create(
      server_pin.data(),
      static_cast<uint32_t>(server_pin.size()),
      server_sha1.data(),
      static_cast<uint32_t>(server_sha1.size()),
      OnEvent,
      &server_sink,
      &server_transport);
  server_sink.transport = server_transport;
  if (create_server != 0) {
    std::cerr << "server create status=0x" << std::hex
              << static_cast<uint32_t>(create_server) << std::dec << std::endl;
  }
  if (!Check(create_server == 0 && server_transport != 0,
             "server transport creation failed")) {
    return 1;
  }

  const auto create_client = bridge.create(
      server_pin.data(),
      static_cast<uint32_t>(server_pin.size()),
      nullptr,
      0,
      OnEvent,
      &client_sink,
      &client_transport);
  client_sink.transport = client_transport;
  if (create_client != 0) {
    std::cerr << "client create status=0x" << std::hex
              << static_cast<uint32_t>(create_client) << std::dec << std::endl;
  }
  if (!Check(create_client == 0 && client_transport != 0,
             "client transport creation failed")) {
    bridge.close(server_transport);
    return 1;
  }

  const auto listen_status = bridge.listen(server_transport, 45887, &listener);
  if (!Check(listen_status == 0 && listener != 0, "listener start failed")) {
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }

  const auto connect_status =
      bridge.connect(client_transport, "127.0.0.1", 45887, &client_connection);
  if (connect_status != 0) {
    std::cerr << "client connect status=0x" << std::hex
              << static_cast<uint32_t>(connect_status) << std::dec << std::endl;
  }
  if (!Check(connect_status == 0 && client_connection != 0,
             "client connection start failed")) {
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }

  Event server_connected;
  Event client_connected;
  if (!Check(
          WaitForEvent(server_sink, AVACA_REMOTE_QUIC_EVENT_CONNECTED, 0,
                       &server_connected) &&
              WaitForEvent(client_sink, AVACA_REMOTE_QUIC_EVENT_CONNECTED,
                           client_connection, &client_connected),
          "authenticated MsQuic connection did not establish")) {
    bridge.close_connection(client_connection);
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  if (!Check(
          server_connected.data.size() == 32 &&
              client_connected.data.size() == 32 &&
              server_connected.data == client_connected.data,
          "TLS exporter channel binding mismatch")) {
    bridge.close_connection(client_connection);
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  std::cout << "PASS: authenticated connection and matching TLS exporter "
               "channel binding "
            << Hex(client_connected.data) << std::endl;

  const auto client_payload = [] {
    std::vector<uint8_t> payload(168);
    for (size_t index = 0; index < payload.size(); ++index) {
      payload[index] = static_cast<uint8_t>(index & 0xff);
    }
    payload[0] = 0x41;
    payload[1] = 0x56;
    payload[2] = 0x41;
    payload[3] = 0x43;
    payload[4] = 0x41;
    return payload;
  }();
  const auto send_client_status = bridge.send(
      client_connection,
      client_payload.data(),
      static_cast<uint32_t>(client_payload.size()),
      0x1001);
  Event server_send_complete;
  Event server_data;
  const bool server_received_client_data =
      WaitForEvent(server_sink, AVACA_REMOTE_QUIC_EVENT_DATA,
                   server_connected.object, &server_data);
  const bool client_send_completed =
      WaitForEvent(client_sink, AVACA_REMOTE_QUIC_EVENT_SEND_COMPLETE,
                   client_connection, &server_send_complete);
  if (send_client_status != 0 || !server_received_client_data ||
      !client_send_completed || server_data.data != client_payload ||
      server_send_complete.operation != 0x1001) {
    std::cerr << "client send status=0x" << std::hex
              << static_cast<uint32_t>(send_client_status) << std::dec
              << " received=" << server_received_client_data
              << " completed=" << client_send_completed << std::endl;
  if (server_received_client_data) {
      std::cerr << "server data length=" << server_data.data.size()
                << " expected=" << client_payload.size() << " equal="
                << (server_data.data == client_payload)
                << " actual=" << Hex(server_data.data)
                << " expected_hex=" << Hex(client_payload)
                << " client_connection=0x" << std::hex << client_connection
                << " server_object=0x" << server_connected.object << std::dec
                << std::endl;
    }
    if (client_send_completed) {
      std::cerr << "client send completion operation=0x" << std::hex
                << server_send_complete.operation << std::dec << std::endl;
    }
    std::cerr << "FAIL: client-to-server data or receive acknowledgement failed"
              << std::endl;
    bridge.close_connection(client_connection);
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  std::cout << "PASS: client-to-server data, send completion, and receive ack"
            << std::endl;

  const std::vector<uint8_t> server_payload = {0x4f, 0x4b, 0x2d, 0x41, 0x56,
                                               0x41, 0x43, 0x41};
  const auto send_server_status = bridge.send(
      server_connected.object,
      server_payload.data(),
      static_cast<uint32_t>(server_payload.size()),
      0x1002);
  Event client_data;
  Event server_send_complete_back;
  const bool client_received_server_data =
      WaitForEvent(client_sink, AVACA_REMOTE_QUIC_EVENT_DATA, client_connection,
                   &client_data);
  const bool server_send_completed =
      WaitForEvent(server_sink, AVACA_REMOTE_QUIC_EVENT_SEND_COMPLETE,
                   server_connected.object, &server_send_complete_back);
  if (send_server_status != 0 || !client_received_server_data ||
      !server_send_completed || client_data.data != server_payload ||
      server_send_complete_back.operation != 0x1002) {
    std::cerr << "server send status=0x" << std::hex
              << static_cast<uint32_t>(send_server_status) << std::dec
              << " received=" << client_received_server_data
              << " completed=" << server_send_completed << std::endl;
    if (client_received_server_data) {
      std::cerr << "client data length=" << client_data.data.size()
                << " expected=" << server_payload.size() << std::endl;
    }
    if (server_send_completed) {
      std::cerr << "server send completion operation=0x" << std::hex
                << server_send_complete_back.operation << std::dec
                << std::endl;
    }
    std::cerr << "FAIL: server-to-client data or send completion failed"
              << std::endl;
    bridge.close_connection(client_connection);
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  std::cout << "PASS: server-to-client data" << std::endl;

  const auto client_followup_payload = [] {
    std::vector<uint8_t> payload(168);
    for (size_t index = 0; index < payload.size(); ++index) {
      payload[index] = static_cast<uint8_t>((0x80 + index) & 0xff);
    }
    payload[0] = 0x46;
    payload[1] = 0x46;
    payload[2] = 0x49;
    return payload;
  }();
  const auto send_client_followup_status = bridge.send(
      client_connection,
      client_followup_payload.data(),
      static_cast<uint32_t>(client_followup_payload.size()),
      0x1003);
  Event server_followup_data;
  Event client_followup_send_complete;
  const bool server_received_client_followup =
      WaitForEvent(server_sink, AVACA_REMOTE_QUIC_EVENT_DATA,
                   server_connected.object, &server_followup_data);
  const bool client_followup_send_completed =
      WaitForEvent(client_sink, AVACA_REMOTE_QUIC_EVENT_SEND_COMPLETE,
                   client_connection, &client_followup_send_complete);
  if (send_client_followup_status != 0 ||
      !server_received_client_followup ||
      !client_followup_send_completed ||
      server_followup_data.data != client_followup_payload ||
      client_followup_send_complete.operation != 0x1003) {
    std::cerr << "client follow-up send status=0x" << std::hex
              << static_cast<uint32_t>(send_client_followup_status) << std::dec
              << " received=" << server_received_client_followup
              << " completed=" << client_followup_send_completed << std::endl;
    std::cerr << "FAIL: sequenced client follow-up data failed" << std::endl;
    bridge.close_connection(client_connection);
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  std::cout << "PASS: sequenced client follow-up data" << std::endl;

  const auto wrong_pin_create = std::vector<uint8_t>(32, 0);
  const auto create_wrong_pin = bridge.create(
      wrong_pin_create.data(),
      static_cast<uint32_t>(wrong_pin_create.size()),
      nullptr,
      0,
      OnEvent,
      &wrong_pin_sink,
      &wrong_pin_transport);
  wrong_pin_sink.transport = wrong_pin_transport;
  if (!Check(create_wrong_pin == 0 && wrong_pin_transport != 0,
             "wrong-pin client transport creation failed")) {
    bridge.close_connection(client_connection);
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  const auto wrong_pin_connect = bridge.connect(
      wrong_pin_transport, "127.0.0.1", 45887, &wrong_pin_connection);
  Event wrong_pin_error;
  const bool wrong_pin_rejected =
      wrong_pin_connect == 0 && wrong_pin_connection != 0 &&
      WaitForEvent(wrong_pin_sink, AVACA_REMOTE_QUIC_EVENT_ERROR,
                   wrong_pin_connection, &wrong_pin_error);
  if (!Check(wrong_pin_rejected &&
                 !HasEvent(wrong_pin_sink, AVACA_REMOTE_QUIC_EVENT_CONNECTED,
                           wrong_pin_connection),
             "wrong certificate pin was not rejected")) {
    if (wrong_pin_connection != 0) {
      bridge.close_connection(wrong_pin_connection);
    }
    bridge.close(wrong_pin_transport);
    bridge.close_connection(client_connection);
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  std::cout << "PASS: wrong certificate pin rejected with status "
            << wrong_pin_error.status << std::endl;

  bridge.close_connection(client_connection);
  if (server_connected.object != 0) {
    WaitForEvent(server_sink, AVACA_REMOTE_QUIC_EVENT_CLOSED,
                 server_connected.object, nullptr);
    server_closed = true;
  }
  WaitForEvent(client_sink, AVACA_REMOTE_QUIC_EVENT_CLOSED, client_connection,
               nullptr);
  client_closed = true;
  bool wrong_pin_closed = true;
  if (wrong_pin_connection != 0) {
    bridge.close_connection(wrong_pin_connection);
    wrong_pin_closed = WaitForEvent(
        wrong_pin_sink,
        AVACA_REMOTE_QUIC_EVENT_CLOSED,
        wrong_pin_connection,
        nullptr,
        10s);
  }
  if (!Check(server_closed && client_closed && wrong_pin_closed,
             "close did not deliver both endpoint closed events")) {
    if (wrong_pin_closed) {
      bridge.close(wrong_pin_transport);
    }
    bridge.close_listener(server_transport, listener);
    bridge.close(client_transport);
    bridge.close(server_transport);
    return 1;
  }
  std::cout << "PASS: asynchronous connection close lifetime" << std::endl;

  bridge.close(wrong_pin_transport);
  bridge.close_listener(server_transport, listener);
  bridge.close(client_transport);
  bridge.close(server_transport);
  std::cout << "PASS: AVACA MsQuic runtime smoke" << std::endl;
  return 0;
}

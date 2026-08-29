#include "include/avaca_player_native/avaca_player_native_plugin.h"

#include "avaca_windows_player_session.h"

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>

namespace {

constexpr char kControlChannel[] = "avaca/player/control";
constexpr char kEventsChannel[] = "avaca/player/events";
constexpr char kViewType[] = "avaca_player_native/video";

using EncodableValue = flutter::EncodableValue;
using EncodableMap = flutter::EncodableMap;

const EncodableValue* MapValue(const EncodableMap& map, const char* key) {
  const auto iterator = map.find(EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::optional<std::string> MapString(const EncodableMap& map,
                                     const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr || value->IsNull()) return std::nullopt;
  const auto* string = std::get_if<std::string>(value);
  return string == nullptr ? std::nullopt : std::optional(*string);
}

std::optional<int64_t> MapInt64(const EncodableMap& map, const char* key) {
  const auto* value = MapValue(map, key);
  return value == nullptr ? std::nullopt : value->TryGetLongValue();
}

std::optional<double> MapDouble(const EncodableMap& map, const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* number = std::get_if<double>(value)) return *number;
  if (const auto integer = value->TryGetLongValue()) {
    return static_cast<double>(*integer);
  }
  return std::nullopt;
}

std::optional<bool> MapBool(const EncodableMap& map, const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr) return std::nullopt;
  const auto* flag = std::get_if<bool>(value);
  return flag == nullptr ? std::nullopt : std::optional(*flag);
}

const EncodableMap* MapMap(const EncodableMap& map, const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr) return nullptr;
  return std::get_if<EncodableMap>(value);
}

EncodableValue SurfaceResult(int64_t texture_id) {
  EncodableMap value;
  value.emplace(EncodableValue("surfaceType"),
                EncodableValue("windowsTexture"));
  value.emplace(EncodableValue("textureId"), EncodableValue(texture_id));
  return EncodableValue(std::move(value));
}

class AvacaPlayerNativePlugin;

class PlayerEventStreamHandler final
    : public flutter::StreamHandler<EncodableValue> {
 public:
  explicit PlayerEventStreamHandler(AvacaPlayerNativePlugin* plugin)
      : plugin_(plugin) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
  OnListenInternal(const EncodableValue* arguments,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&&
                       events) override;

  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
  OnCancelInternal(const EncodableValue* arguments) override;

 private:
  AvacaPlayerNativePlugin* const plugin_;
};

class AvacaPlayerNativePlugin final : public flutter::Plugin {
 public:
  explicit AvacaPlayerNativePlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar),
        control_channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
            registrar_->messenger(), kControlChannel,
            &flutter::StandardMethodCodec::GetInstance())),
        events_channel_(std::make_unique<flutter::EventChannel<EncodableValue>>(
            registrar_->messenger(), kEventsChannel,
            &flutter::StandardMethodCodec::GetInstance())) {
    control_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
    events_channel_->SetStreamHandler(
        std::make_unique<PlayerEventStreamHandler>(this));
  }

  ~AvacaPlayerNativePlugin() override {
    events_channel_->SetStreamHandler(nullptr);
    control_channel_->SetMethodCallHandler(nullptr);

    std::map<std::string, std::shared_ptr<AvacaWindowsPlayerSession>> sessions;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      sessions.swap(sessions_);
      event_sink_.reset();
    }
    for (auto& entry : sessions) {
      entry.second->Close();
    }
  }

  void SetEventSink(
      std::shared_ptr<flutter::EventSink<EncodableValue>> event_sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    event_sink_ = std::move(event_sink);
  }

  void ClearEventSink() {
    std::lock_guard<std::mutex> lock(mutex_);
    event_sink_.reset();
  }

  void Emit(EncodableValue event) {
    std::shared_ptr<flutter::EventSink<EncodableValue>> sink;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      sink = event_sink_;
    }
    if (sink != nullptr) sink->Success(event);
  }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* arguments = call.arguments();
    const auto* argument_map =
        arguments == nullptr ? nullptr : std::get_if<EncodableMap>(arguments);

    if (call.method_name() == "createSession") {
      HandleCreateSession(argument_map, std::move(result));
      return;
    }
    if (argument_map == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Player arguments are missing.");
      return;
    }

    const auto session_id = MapString(*argument_map, "sessionId");
    if (!session_id || session_id->empty()) {
      result->Error("INVALID_SESSION", "The player session id is missing.");
      return;
    }

    std::shared_ptr<AvacaWindowsPlayerSession> session;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const auto iterator = sessions_.find(*session_id);
      if (iterator != sessions_.end()) session = iterator->second;
    }
    if (session == nullptr) {
      result->Error("PLAYER_SESSION_NOT_FOUND",
                    "The player session has not been created.");
      return;
    }

    AvacaWindowsPlayerSession::OperationResult operation;
    const auto method = call.method_name();
    if (method == "open") {
      const auto* request = MapMap(*argument_map, "request");
      operation = request == nullptr
                      ? AvacaWindowsPlayerSession::OperationResult::Failure(
                            "INVALID_REQUEST", "The player request is missing.")
                      : session->Open(*request);
    } else if (method == "play") {
      operation = session->Play();
    } else if (method == "pause") {
      operation = session->Pause();
    } else if (method == "seek") {
      operation = session->Seek(MapInt64(*argument_map, "positionMs").value_or(0),
                                MapInt64(*argument_map, "seekGeneration")
                                    .value_or(0));
    } else if (method == "setSpeed") {
      operation = session->SetSpeed(
          MapDouble(*argument_map, "speed").value_or(1.0));
    } else if (method == "selectSubtitle") {
      const auto* value = MapValue(*argument_map, "trackId");
      std::optional<std::string> track_id;
      if (value != nullptr && !value->IsNull()) {
        const auto* string = std::get_if<std::string>(value);
        if (string == nullptr) {
          operation = AvacaWindowsPlayerSession::OperationResult::Failure(
              "INVALID_SUBTITLE", "The subtitle track id is invalid.");
        } else {
          track_id = *string;
        }
      }
      if (operation.error_code.empty()) {
        operation = session->SelectSubtitle(
            track_id ? &track_id.value() : nullptr);
      }
    } else if (method == "setFullscreen") {
      operation = session->SetFullscreen(
          MapBool(*argument_map, "fullscreen").value_or(false));
    } else if (method == "getDiagnostics") {
      operation = session->GetDiagnostics();
    } else if (method == "close") {
      operation = session->Close();
      if (operation.ok) {
        std::lock_guard<std::mutex> lock(mutex_);
        sessions_.erase(*session_id);
      }
    } else {
      result->NotImplemented();
      return;
    }

    CompleteResult(std::move(result), operation);
  }

  void HandleCreateSession(
      const EncodableMap* arguments,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (arguments == nullptr) {
      result->Error("INVALID_ARGUMENTS", "Player arguments are missing.");
      return;
    }
    const auto session_id = MapString(*arguments, "sessionId");
    if (!session_id || session_id->empty()) {
      result->Error("INVALID_SESSION", "The player session id is missing.");
      return;
    }

    std::shared_ptr<AvacaWindowsPlayerSession> session;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      const auto iterator = sessions_.find(*session_id);
      if (iterator != sessions_.end()) session = iterator->second;
    }
    if (session != nullptr) {
      CompleteResult(std::move(result),
                     AvacaWindowsPlayerSession::OperationResult::Success(
                         SurfaceResult(session->texture_id())));
      return;
    }

    void* native_window = nullptr;
    if (registrar_ != nullptr && registrar_->GetView() != nullptr) {
      native_window = registrar_->GetView()->GetNativeWindow();
    }
    session = std::make_shared<AvacaWindowsPlayerSession>(
        *session_id, registrar_ == nullptr ? nullptr : registrar_->texture_registrar(),
        native_window,
        [this](EncodableValue event) { Emit(std::move(event)); });
    const auto initialized = session->Initialize();
    if (!initialized.ok) {
      CompleteResult(std::move(result), initialized);
      return;
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      sessions_.emplace(*session_id, session);
    }
    CompleteResult(std::move(result),
                   AvacaWindowsPlayerSession::OperationResult::Success(
                       SurfaceResult(session->texture_id())));
  }

  static void CompleteResult(
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result,
      const AvacaWindowsPlayerSession::OperationResult& operation) {
    if (!operation.ok) {
      result->Error(operation.error_code, operation.error_message);
    } else if (operation.value.IsNull()) {
      result->Success();
    } else {
      result->Success(operation.value);
    }
  }

  flutter::PluginRegistrarWindows* const registrar_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> control_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> events_channel_;

  std::mutex mutex_;
  std::map<std::string, std::shared_ptr<AvacaWindowsPlayerSession>> sessions_;
  std::shared_ptr<flutter::EventSink<EncodableValue>> event_sink_;

  friend class PlayerEventStreamHandler;
};

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
PlayerEventStreamHandler::OnListenInternal(
    const EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
  plugin_->SetEventSink(std::shared_ptr<flutter::EventSink<EncodableValue>>(
      events.release()));
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
PlayerEventStreamHandler::OnCancelInternal(const EncodableValue* arguments) {
  plugin_->ClearEventSink();
  return nullptr;
}

}  // namespace

void AvacaPlayerNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* plugin_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  plugin_registrar->AddPlugin(
      std::make_unique<AvacaPlayerNativePlugin>(plugin_registrar));
}

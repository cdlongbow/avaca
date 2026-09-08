#include "include/avaca_player_native/avaca_player_native_plugin.h"

#include "avaca_windows_player_session.h"
#include "avaca_remote_core/avaca_windows_discovery.h"

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <shlobj.h>
#include <wincrypt.h>

#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr char kControlChannel[] = "avaca/player/control";
constexpr char kEventsChannel[] = "avaca/player/events";
constexpr char kProfileStoreChannel[] = "avaca/remote/profile_store";
constexpr char kDiscoveryChannel[] = "avaca/remote/discovery";
constexpr char kDiscoveryEventsChannel[] = "avaca/remote/discovery_events";
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

bool SafeProfileKey(const std::string& key) {
  if (key.empty() || key.size() > 320) return false;
  for (const auto character : key) {
    if (!((character >= 'A' && character <= 'Z') ||
          (character >= 'a' && character <= 'z') ||
          (character >= '0' && character <= '9') || character == '.' ||
          character == '_' || character == '-' || character == '~')) {
      return false;
    }
  }
  return true;
}

std::optional<std::wstring> ProfilePath(const std::string& key,
                                        bool create_directory) {
  if (!SafeProfileKey(key)) return std::nullopt;
  PWSTR local_app_data = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT,
                                  nullptr, &local_app_data)) ||
      local_app_data == nullptr) {
    return std::nullopt;
  }
  const std::filesystem::path directory =
      std::filesystem::path(local_app_data) / L"AVACA" / L"remote-profiles";
  CoTaskMemFree(local_app_data);
  std::error_code error;
  if (create_directory) std::filesystem::create_directories(directory, error);
  if (error) return std::nullopt;
  return (directory / (std::wstring(key.begin(), key.end()) + L".bin"))
      .wstring();
}

bool ProtectProfile(const std::vector<uint8_t>& cleartext,
                    std::vector<uint8_t>* protected_blob) {
  if (protected_blob == nullptr || cleartext.empty() ||
      cleartext.size() > MAXDWORD) {
    return false;
  }
  DATA_BLOB input = {static_cast<DWORD>(cleartext.size()),
                     const_cast<BYTE*>(cleartext.data())};
  DATA_BLOB output = {};
  if (!CryptProtectData(&input, L"AVACA remote profile", nullptr, nullptr,
                        nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return false;
  }
  protected_blob->assign(output.pbData, output.pbData + output.cbData);
  LocalFree(output.pbData);
  return true;
}

bool UnprotectProfile(const std::vector<uint8_t>& protected_blob,
                      std::vector<uint8_t>* cleartext) {
  if (cleartext == nullptr || protected_blob.empty() ||
      protected_blob.size() > MAXDWORD) {
    return false;
  }
  DATA_BLOB input = {static_cast<DWORD>(protected_blob.size()),
                     const_cast<BYTE*>(protected_blob.data())};
  DATA_BLOB output = {};
  if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &output)) {
    return false;
  }
  cleartext->assign(output.pbData, output.pbData + output.cbData);
  SecureZeroMemory(output.pbData, output.cbData);
  LocalFree(output.pbData);
  return true;
}

bool WriteProtectedProfile(const std::string& key,
                           const std::vector<uint8_t>& cleartext) {
  const auto path = ProfilePath(key, true);
  if (!path) return false;
  std::vector<uint8_t> protected_blob;
  if (!ProtectProfile(cleartext, &protected_blob)) return false;
  const auto temporary = *path + L".tmp";
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    if (!output) return false;
    output.write(reinterpret_cast<const char*>(protected_blob.data()),
                 static_cast<std::streamsize>(protected_blob.size()));
    output.flush();
    if (!output) return false;
  }
  return MoveFileExW(temporary.c_str(), path->c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

std::optional<std::vector<uint8_t>> ReadProtectedProfile(
    const std::string& key) {
  const auto path = ProfilePath(key, false);
  if (!path) return std::nullopt;
  std::ifstream input(*path, std::ios::binary);
  if (!input) return std::nullopt;
  const auto size = std::filesystem::file_size(*path);
  if (size == 0 || size > 1024 * 1024) return std::nullopt;
  std::vector<uint8_t> protected_blob(static_cast<size_t>(size));
  input.read(reinterpret_cast<char*>(protected_blob.data()),
             static_cast<std::streamsize>(protected_blob.size()));
  if (!input) return std::nullopt;
  std::vector<uint8_t> cleartext;
  if (!UnprotectProfile(protected_blob, &cleartext)) return std::nullopt;
  return cleartext;
}

EncodableValue SurfaceResult(int64_t texture_id) {
  EncodableMap value;
  value.emplace(EncodableValue("surfaceType"),
                EncodableValue("windowsTexture"));
  value.emplace(EncodableValue("textureId"), EncodableValue(texture_id));
  return EncodableValue(std::move(value));
}

class AvacaPlayerNativePlugin;

class DiscoveryEventStreamHandler final
    : public flutter::StreamHandler<EncodableValue> {
 public:
  explicit DiscoveryEventStreamHandler(AvacaPlayerNativePlugin* plugin)
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
        profile_channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
            registrar_->messenger(), kProfileStoreChannel,
            &flutter::StandardMethodCodec::GetInstance())),
        discovery_channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
            registrar_->messenger(), kDiscoveryChannel,
            &flutter::StandardMethodCodec::GetInstance())),
        events_channel_(std::make_unique<flutter::EventChannel<EncodableValue>>(
            registrar_->messenger(), kEventsChannel,
            &flutter::StandardMethodCodec::GetInstance())),
        discovery_events_channel_(
            std::make_unique<flutter::EventChannel<EncodableValue>>(
                registrar_->messenger(), kDiscoveryEventsChannel,
                &flutter::StandardMethodCodec::GetInstance())) {
    control_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
    profile_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleProfileStoreCall(call, std::move(result));
        });
    discovery_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleDiscoveryCall(call, std::move(result));
        });
    events_channel_->SetStreamHandler(
        std::make_unique<PlayerEventStreamHandler>(this));
    discovery_events_channel_->SetStreamHandler(
        std::make_unique<DiscoveryEventStreamHandler>(this));
  }

  ~AvacaPlayerNativePlugin() override {
    StopDiscovery();
    discovery_events_channel_->SetStreamHandler(nullptr);
    discovery_channel_->SetMethodCallHandler(nullptr);
    events_channel_->SetStreamHandler(nullptr);
    control_channel_->SetMethodCallHandler(nullptr);
    profile_channel_->SetMethodCallHandler(nullptr);

    std::map<std::string, std::shared_ptr<AvacaWindowsPlayerSession>> sessions;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      sessions.swap(sessions_);
      event_sink_.reset();
      discovery_event_sink_.reset();
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

  void SetDiscoveryEventSink(
      std::shared_ptr<flutter::EventSink<EncodableValue>> event_sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    discovery_event_sink_ = std::move(event_sink);
  }

  void ClearDiscoveryEventSink() {
    std::lock_guard<std::mutex> lock(mutex_);
    discovery_event_sink_.reset();
  }

 private:
  void EmitDiscovery(
      avaca_remote_core::AvacaWindowsDiscoveryCandidate candidate) {
    EncodableMap txt;
    for (const auto& entry : candidate.txt) {
      txt.emplace(EncodableValue(entry.first), EncodableValue(entry.second));
    }
    EncodableMap event;
    event.emplace(EncodableValue("host"), EncodableValue(candidate.host));
    event.emplace(EncodableValue("port"),
                  EncodableValue(static_cast<int64_t>(candidate.port)));
    event.emplace(EncodableValue("txt"), EncodableValue(std::move(txt)));

    std::shared_ptr<flutter::EventSink<EncodableValue>> sink;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      sink = discovery_event_sink_;
    }
    if (sink != nullptr) sink->Success(EncodableValue(std::move(event)));
  }

  void HandleDiscoveryCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (call.method_name() == "start") {
      if (!discovery_) {
        discovery_ = std::make_unique<avaca_remote_core::AvacaWindowsDnsSd>();
      }
      const bool started = discovery_->StartBrowsing(
          "_avaca-remote._udp",
          [this](avaca_remote_core::AvacaWindowsDiscoveryCandidate candidate) {
            EmitDiscovery(std::move(candidate));
          });
      if (!started) {
        result->Error("DISCOVERY_START_FAILED",
                      "Windows DNS-SD discovery could not start.");
      } else {
        result->Success();
      }
      return;
    }
    if (call.method_name() == "stop") {
      StopDiscovery();
      result->Success();
      return;
    }
    result->NotImplemented();
  }

  void StopDiscovery() {
    if (discovery_) discovery_->StopBrowsing();
  }

  void HandleProfileStoreCall(
      const flutter::MethodCall<EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    const auto* arguments = call.arguments();
    const auto* map = arguments == nullptr ? nullptr
                                           : std::get_if<EncodableMap>(arguments);
    const auto key = map == nullptr ? std::optional<std::string>()
                                    : MapString(*map, "key");
    if (!key || !SafeProfileKey(*key)) {
      result->Error("INVALID_PROFILE_KEY", "The remote profile key is invalid.");
      return;
    }
    if (call.method_name() == "write") {
      const auto* value = map == nullptr ? nullptr : MapValue(*map, "value");
      const auto* bytes = value == nullptr
                              ? nullptr
                              : std::get_if<std::vector<uint8_t>>(value);
      if (bytes == nullptr || bytes->empty() || bytes->size() > 64 * 1024 ||
          !WriteProtectedProfile(*key, *bytes)) {
        result->Error("PROFILE_STORAGE", "Secure remote profile write failed.");
        return;
      }
      result->Success();
      return;
    }
    if (call.method_name() == "read") {
      const auto value = ReadProtectedProfile(*key);
      if (!value) {
        result->Success();
      } else {
        result->Success(EncodableValue(*value));
      }
      return;
    }
    if (call.method_name() == "delete") {
      const auto path = ProfilePath(*key, false);
      if (path && !DeleteFileW(path->c_str()) && GetLastError() != ERROR_FILE_NOT_FOUND) {
        result->Error("PROFILE_STORAGE", "Secure remote profile delete failed.");
        return;
      }
      result->Success();
      return;
    }
    result->NotImplemented();
  }

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
    if (method == "configureRemote") {
      const auto* profile = MapMap(*argument_map, "profile");
      operation = profile == nullptr
                      ? AvacaWindowsPlayerSession::OperationResult::Failure(
                            "INVALID_PROFILE", "The remote profile is missing.")
                      : session->ConfigureRemote(*profile);
    } else if (method == "open") {
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
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> profile_channel_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> discovery_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> events_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>>
      discovery_events_channel_;

  std::mutex mutex_;
  std::map<std::string, std::shared_ptr<AvacaWindowsPlayerSession>> sessions_;
  std::shared_ptr<flutter::EventSink<EncodableValue>> event_sink_;
  std::shared_ptr<flutter::EventSink<EncodableValue>> discovery_event_sink_;
  std::unique_ptr<avaca_remote_core::AvacaWindowsDnsSd> discovery_;

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

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
DiscoveryEventStreamHandler::OnListenInternal(
    const EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<EncodableValue>>&& events) {
  plugin_->SetDiscoveryEventSink(
      std::shared_ptr<flutter::EventSink<EncodableValue>>(events.release()));
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
DiscoveryEventStreamHandler::OnCancelInternal(
    const EncodableValue* arguments) {
  plugin_->ClearDiscoveryEventSink();
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

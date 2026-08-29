#ifndef AVACA_PLAYER_NATIVE_WINDOWS_PLAYER_SESSION_H_
#define AVACA_PLAYER_NATIVE_WINDOWS_PLAYER_SESSION_H_

#include <flutter/encodable_value.h>
#include <flutter/texture_registrar.h>

#include <cstdint>
#include <atomic>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

struct mpv_event;

class AvacaWindowsPlayerSession final
    : public std::enable_shared_from_this<AvacaWindowsPlayerSession> {
 public:
  struct OperationResult {
    bool ok = false;
    std::string error_code;
    std::string error_message;
    flutter::EncodableValue value;

    static OperationResult Success();
    static OperationResult Success(flutter::EncodableValue value);
    static OperationResult Failure(std::string error_code,
                                   std::string error_message);
  };

  using EmitCallback = std::function<void(flutter::EncodableValue)>;

  AvacaWindowsPlayerSession(std::string session_id,
                            flutter::TextureRegistrar* texture_registrar,
                            void* native_window,
                            EmitCallback emit_callback);
  ~AvacaWindowsPlayerSession();

  AvacaWindowsPlayerSession(const AvacaWindowsPlayerSession&) = delete;
  AvacaWindowsPlayerSession& operator=(const AvacaWindowsPlayerSession&) =
      delete;

  OperationResult Initialize();
  OperationResult Open(const flutter::EncodableMap& request);
  OperationResult Play();
  OperationResult Pause();
  OperationResult Seek(int64_t position_ms, int64_t generation);
  OperationResult SetSpeed(double speed);
  OperationResult SelectSubtitle(const std::string* track_id);
  OperationResult SetFullscreen(bool fullscreen);
  OperationResult GetDiagnostics();
  OperationResult Close();

  int64_t texture_id() const { return texture_id_; }

 private:
  struct NativeState;

  OperationResult RunSync(
      std::function<OperationResult()> operation);
  void WorkerLoop();
  void WakeWorker();
  OperationResult InitializeOnWorker();
  OperationResult OpenOnWorker(const flutter::EncodableMap& request);
  OperationResult PlayOnWorker();
  OperationResult PauseOnWorker();
  OperationResult SeekOnWorker(int64_t position_ms, int64_t generation);
  OperationResult SetSpeedOnWorker(double speed);
  OperationResult SelectSubtitleOnWorker(const std::string* track_id);
  OperationResult SetFullscreenOnWorker(bool fullscreen);
  OperationResult GetDiagnosticsOnWorker();
  OperationResult CloseOnWorker();
  void ProcessMpvEvent(const mpv_event* event);
  void RefreshStateFromMpv();
  void RefreshSubtitleTracks();
  void RenderFrame();
  void EmitState(const char* phase_override = nullptr,
                 bool subtitle_selection_changed = false,
                 std::optional<int64_t> seek_generation = std::nullopt);
  void EmitError(const char* error_type,
                 const char* localized_message_key,
                 const char* diagnostic_code,
                 bool recoverable);
  void RequestRender();
  const FlutterDesktopGpuSurfaceDescriptor* ObtainDescriptor(
      size_t width,
      size_t height);
  static void ReleaseDescriptor(void* release_context);
  static void OnMpvRenderUpdate(void* callback_context);

  const std::string session_id_;
  flutter::TextureRegistrar* const texture_registrar_;
  void* const native_window_;
  const EmitCallback emit_callback_;

  std::unique_ptr<NativeState> native_state_;
  std::unique_ptr<flutter::TextureVariant> texture_variant_;
  int64_t texture_id_ = -1;

  class CommandQueue;
  std::unique_ptr<CommandQueue> command_queue_;
  std::thread worker_thread_;
  std::atomic<bool> stop_requested_{false};
  std::mutex lifecycle_mutex_;
};

#endif  // AVACA_PLAYER_NATIVE_WINDOWS_PLAYER_SESSION_H_

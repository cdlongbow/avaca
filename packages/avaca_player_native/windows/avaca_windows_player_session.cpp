#include "avaca_windows_player_session.h"

#include "angle_abi.h"
#include "mpv_abi.h"

#include <flutter/texture_registrar.h>

#include <d3d11.h>
#include <dxgi.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <future>
#include <iomanip>
#include <limits>
#include <locale>
#include <map>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;
using EncodableMap = flutter::EncodableMap;
using EncodableValue = flutter::EncodableValue;

constexpr int kDefaultWidth = 1280;
constexpr int kDefaultHeight = 720;
constexpr int kMinimumDimension = 64;
constexpr int kMaximumDimension = 4096;

int ClampDimension(size_t value, int fallback) {
  const auto bounded = value == 0 ? static_cast<size_t>(fallback) : value;
  return std::clamp(static_cast<int>(std::min<size_t>(bounded,
                                                       kMaximumDimension)),
                    kMinimumDimension, kMaximumDimension);
}

std::wstring ExecutableDirectory() {
  std::vector<wchar_t> buffer(1024);
  for (;;) {
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                             static_cast<DWORD>(buffer.size()));
    if (length == 0) return L".";
    if (length < buffer.size() - 1) {
      std::wstring path(buffer.data(), length);
      const auto separator = path.find_last_of(L"\\/");
      return separator == std::wstring::npos ? L"." : path.substr(0, separator);
    }
    buffer.resize(buffer.size() * 2);
    if (buffer.size() > 32768) return L".";
  }
}

std::string Utf8Path(const std::wstring& path) {
  if (path.empty()) return {};
  const int length = WideCharToMultiByte(
      CP_UTF8, 0, path.data(), static_cast<int>(path.size()), nullptr, 0,
      nullptr, nullptr);
  if (length <= 0) return {};
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, path.data(), static_cast<int>(path.size()),
                      result.data(), length, nullptr, nullptr);
  return result;
}

std::string ModulePath(HMODULE module) {
  if (module == nullptr) return {};
  std::vector<wchar_t> buffer(1024);
  for (;;) {
    const DWORD length = GetModuleFileNameW(
        module, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return {};
    if (length < buffer.size() - 1) {
      return Utf8Path(std::wstring(buffer.data(), length));
    }
    buffer.resize(buffer.size() * 2);
    if (buffer.size() > 32768) return {};
  }
}

HMODULE LoadAdjacentLibrary(const wchar_t* name) {
  const std::wstring path = ExecutableDirectory() + L"\\" + name;
  return LoadLibraryExW(path.c_str(), nullptr,
                        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                            LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
}

template <typename Function>
bool LoadSymbol(HMODULE module, const char* name, Function* function) {
  if (module == nullptr || function == nullptr) return false;
  *function = reinterpret_cast<Function>(::GetProcAddress(module, name));
  return *function != nullptr;
}

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

const EncodableMap* MapMap(const EncodableMap& map, const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr) return nullptr;
  return std::get_if<EncodableMap>(value);
}

std::string DoubleString(double value) {
  std::ostringstream stream;
  stream.imbue(std::locale::classic());
  stream << std::fixed << std::setprecision(3) << value;
  return stream.str();
}

std::string FeatureLevelString(D3D_FEATURE_LEVEL level) {
  switch (level) {
    case D3D_FEATURE_LEVEL_12_2:
      return "12_2";
    case D3D_FEATURE_LEVEL_12_1:
      return "12_1";
    case D3D_FEATURE_LEVEL_12_0:
      return "12_0";
    case D3D_FEATURE_LEVEL_11_1:
      return "11_1";
    case D3D_FEATURE_LEVEL_11_0:
      return "11_0";
    case D3D_FEATURE_LEVEL_10_1:
      return "10_1";
    case D3D_FEATURE_LEVEL_10_0:
      return "10_0";
    case D3D_FEATURE_LEVEL_9_3:
      return "9_3";
    default:
      return "unknown";
  }
}

std::string HResultString(HRESULT result) {
  std::ostringstream stream;
  stream << "0x" << std::uppercase << std::hex
         << static_cast<unsigned long>(result);
  return stream.str();
}

struct MpvLibrary final {
  HMODULE module = nullptr;
  std::string loaded_path;
  mpv_client_api_version_fn client_api_version = nullptr;
  mpv_create_fn create = nullptr;
  mpv_initialize_fn initialize = nullptr;
  mpv_terminate_destroy_fn terminate_destroy = nullptr;
  mpv_set_option_string_fn set_option_string = nullptr;
  mpv_set_property_string_fn set_property_string = nullptr;
  mpv_get_property_fn get_property = nullptr;
  mpv_get_property_string_fn get_property_string = nullptr;
  mpv_observe_property_fn observe_property = nullptr;
  mpv_request_event_fn request_event = nullptr;
  mpv_command_fn command = nullptr;
  mpv_wait_event_fn wait_event = nullptr;
  mpv_wakeup_fn wakeup = nullptr;
  mpv_free_fn free = nullptr;
  mpv_free_node_contents_fn free_node_contents = nullptr;
  mpv_error_string_fn error_string = nullptr;
  mpv_render_context_create_fn render_context_create = nullptr;
  mpv_render_context_set_update_callback_fn
      render_context_set_update_callback = nullptr;
  mpv_render_context_update_fn render_context_update = nullptr;
  mpv_render_context_render_fn render_context_render = nullptr;
  mpv_render_context_report_swap_fn render_context_report_swap = nullptr;
  mpv_render_context_free_fn render_context_free = nullptr;

  bool Load() {
    module = LoadAdjacentLibrary(L"libmpv-2.dll");
    if (module == nullptr) return false;
    loaded_path = ModulePath(module);

    const bool complete =
        LoadSymbol(module, "mpv_client_api_version", &client_api_version) &&
        LoadSymbol(module, "mpv_create", &create) &&
        LoadSymbol(module, "mpv_initialize", &initialize) &&
        LoadSymbol(module, "mpv_terminate_destroy", &terminate_destroy) &&
        LoadSymbol(module, "mpv_set_option_string", &set_option_string) &&
        LoadSymbol(module, "mpv_set_property_string", &set_property_string) &&
        LoadSymbol(module, "mpv_get_property", &get_property) &&
        LoadSymbol(module, "mpv_get_property_string", &get_property_string) &&
        LoadSymbol(module, "mpv_observe_property", &observe_property) &&
        LoadSymbol(module, "mpv_request_event", &request_event) &&
        LoadSymbol(module, "mpv_command", &command) &&
        LoadSymbol(module, "mpv_wait_event", &wait_event) &&
        LoadSymbol(module, "mpv_wakeup", &wakeup) &&
        LoadSymbol(module, "mpv_free", &free) &&
        LoadSymbol(module, "mpv_free_node_contents", &free_node_contents) &&
        LoadSymbol(module, "mpv_error_string", &error_string) &&
        LoadSymbol(module, "mpv_render_context_create",
                   &render_context_create) &&
        LoadSymbol(module, "mpv_render_context_set_update_callback",
                   &render_context_set_update_callback) &&
        LoadSymbol(module, "mpv_render_context_update",
                   &render_context_update) &&
        LoadSymbol(module, "mpv_render_context_render",
                   &render_context_render) &&
        LoadSymbol(module, "mpv_render_context_report_swap",
                   &render_context_report_swap) &&
        LoadSymbol(module, "mpv_render_context_free", &render_context_free);
    if (!complete) {
      Unload();
      return false;
    }
    return true;
  }

  void Unload() {
    if (module != nullptr) FreeLibrary(module);
    module = nullptr;
    loaded_path.clear();
    client_api_version = nullptr;
    create = nullptr;
    initialize = nullptr;
    terminate_destroy = nullptr;
    set_option_string = nullptr;
    set_property_string = nullptr;
    get_property = nullptr;
    get_property_string = nullptr;
    observe_property = nullptr;
    request_event = nullptr;
    command = nullptr;
    wait_event = nullptr;
    wakeup = nullptr;
    free = nullptr;
    free_node_contents = nullptr;
    error_string = nullptr;
    render_context_create = nullptr;
    render_context_set_update_callback = nullptr;
    render_context_update = nullptr;
    render_context_render = nullptr;
    render_context_report_swap = nullptr;
    render_context_free = nullptr;
  }
};

struct AngleLibrary final {
  HMODULE egl_module = nullptr;
  HMODULE gles_module = nullptr;
  std::string egl_loaded_path;
  std::string gles_loaded_path;

  eglGetProcAddress_fn egl_get_proc_address = nullptr;
  eglGetPlatformDisplayEXT_fn egl_get_platform_display = nullptr;
  eglInitialize_fn egl_initialize = nullptr;
  eglTerminate_fn egl_terminate = nullptr;
  eglChooseConfig_fn egl_choose_config = nullptr;
  eglBindAPI_fn egl_bind_api = nullptr;
  eglCreateContext_fn egl_create_context = nullptr;
  eglDestroyContext_fn egl_destroy_context = nullptr;
  eglCreatePbufferFromClientBuffer_fn egl_create_pbuffer = nullptr;
  eglDestroySurface_fn egl_destroy_surface = nullptr;
  eglMakeCurrent_fn egl_make_current = nullptr;
  eglBindTexImage_fn egl_bind_tex_image = nullptr;
  eglReleaseTexImage_fn egl_release_tex_image = nullptr;
  eglGetError_fn egl_get_error = nullptr;
  glFinish_fn gl_finish = nullptr;
  glGetString_fn gl_get_string = nullptr;

  EGLDisplay display = EGL_NO_DISPLAY;
  EGLConfig config = nullptr;
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface surface = EGL_NO_SURFACE;
  std::string load_error;
  std::string surface_error;

  bool Load() {
    egl_module = LoadAdjacentLibrary(L"libEGL.dll");
    gles_module = LoadAdjacentLibrary(L"libGLESv2.dll");
    if (egl_module == nullptr || gles_module == nullptr) {
      load_error = "angle_dll_load_" + std::to_string(GetLastError());
      Unload();
      return false;
    }
    egl_loaded_path = ModulePath(egl_module);
    gles_loaded_path = ModulePath(gles_module);
    const bool complete =
        LoadSymbol(egl_module, "eglGetProcAddress", &egl_get_proc_address) &&
        LoadSymbol(egl_module, "eglInitialize", &egl_initialize) &&
        LoadSymbol(egl_module, "eglTerminate", &egl_terminate) &&
        LoadSymbol(egl_module, "eglChooseConfig", &egl_choose_config) &&
        LoadSymbol(egl_module, "eglBindAPI", &egl_bind_api) &&
        LoadSymbol(egl_module, "eglCreateContext", &egl_create_context) &&
        LoadSymbol(egl_module, "eglDestroyContext", &egl_destroy_context) &&
        LoadSymbol(egl_module, "eglCreatePbufferFromClientBuffer",
                   &egl_create_pbuffer) &&
        LoadSymbol(egl_module, "eglDestroySurface", &egl_destroy_surface) &&
        LoadSymbol(egl_module, "eglMakeCurrent", &egl_make_current) &&
        LoadSymbol(egl_module, "eglBindTexImage", &egl_bind_tex_image) &&
        LoadSymbol(egl_module, "eglReleaseTexImage", &egl_release_tex_image) &&
        LoadSymbol(egl_module, "eglGetError", &egl_get_error) &&
        LoadSymbol(gles_module, "glFinish", &gl_finish) &&
        LoadSymbol(gles_module, "glGetString", &gl_get_string);
    if (!complete) {
      load_error = "angle_egl_symbol_missing";
      Unload();
      return false;
    }
    egl_get_platform_display = reinterpret_cast<eglGetPlatformDisplayEXT_fn>(
        egl_get_proc_address("eglGetPlatformDisplayEXT"));
    if (egl_get_platform_display == nullptr) {
      LoadSymbol(egl_module, "eglGetPlatformDisplayEXT",
                 &egl_get_platform_display);
    }
    if (egl_get_platform_display == nullptr) {
      load_error = "angle_platform_display_symbol_missing";
      Unload();
      return false;
    }
    return true;
  }

  std::string LastFailure(const char* stage) const {
    if (!load_error.empty()) return load_error;
    if (!surface_error.empty()) return surface_error;
    const auto error = egl_get_error == nullptr ? -1 : egl_get_error();
    return std::string(stage) + "_egl_0x" +
           [&error]() {
             char value[16]{};
             std::snprintf(value, sizeof(value), "%04X",
                           static_cast<unsigned int>(error));
             return std::string(value);
           }();
  }

  void* GetProcAddress(const char* name) const {
    if (name == nullptr) return nullptr;
    if (egl_get_proc_address != nullptr) {
      if (void* value = egl_get_proc_address(name); value != nullptr) {
        return value;
      }
    }
    if (gles_module != nullptr) {
      if (void* value = reinterpret_cast<void*>(
              ::GetProcAddress(gles_module, name));
          value != nullptr) {
        return value;
      }
    }
    if (egl_module != nullptr) {
      return reinterpret_cast<void*>(::GetProcAddress(egl_module, name));
    }
    return nullptr;
  }

  bool InitializeDisplay() {
    const EGLint display_attributes[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE,
        EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
        EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE,
        EGL_TRUE,
        EGL_EXPERIMENTAL_PRESENT_PATH_ANGLE,
        EGL_EXPERIMENTAL_PRESENT_PATH_FAST_ANGLE,
        EGL_NONE,
    };
    display = egl_get_platform_display(EGL_PLATFORM_ANGLE_ANGLE, nullptr,
                                       display_attributes);
    if (display == EGL_NO_DISPLAY || egl_initialize(display, nullptr, nullptr) !=
                                        EGL_TRUE) {
      return false;
    }
    if (egl_bind_api(EGL_OPENGL_ES_API) != EGL_TRUE) return false;

    const EGLint config_attributes[] = {
        EGL_RED_SIZE,
        8,
        EGL_GREEN_SIZE,
        8,
        EGL_BLUE_SIZE,
        8,
        EGL_ALPHA_SIZE,
        8,
        EGL_DEPTH_SIZE,
        8,
        EGL_STENCIL_SIZE,
        8,
        EGL_NONE,
    };
    EGLint count = 0;
    if (egl_choose_config(display, config_attributes, &config, 1, &count) !=
            EGL_TRUE ||
        count < 1 || config == nullptr) {
      return false;
    }
    const EGLint context_attributes[] = {
        EGL_CONTEXT_CLIENT_VERSION,
        2,
        EGL_NONE,
    };
    context = egl_create_context(display, config, EGL_NO_CONTEXT,
                                 context_attributes);
    return context != EGL_NO_CONTEXT;
  }

  bool CreateSurface(HANDLE shared_handle, int width, int height) {
    surface_error.clear();
    if (display == EGL_NO_DISPLAY || context == EGL_NO_CONTEXT ||
        shared_handle == nullptr) {
      surface_error = "angle_surface_precondition";
      return false;
    }
    const EGLint surface_attributes[] = {
        EGL_WIDTH,
        width,
        EGL_HEIGHT,
        height,
        EGL_TEXTURE_FORMAT,
        EGL_TEXTURE_RGBA,
        EGL_TEXTURE_TARGET,
        EGL_TEXTURE_2D,
        EGL_NONE,
    };
    surface = egl_create_pbuffer(
        display, EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE,
        reinterpret_cast<EGLClientBuffer>(shared_handle), config,
        surface_attributes);
    if (surface == EGL_NO_SURFACE) {
      surface_error = LastFailure("angle_create_pbuffer");
      return false;
    }
    if (egl_make_current(display, surface, surface, context) != EGL_TRUE) {
      surface_error = LastFailure("angle_make_current");
      egl_destroy_surface(display, surface);
      surface = EGL_NO_SURFACE;
      return false;
    }
    if (egl_bind_tex_image(display, surface, EGL_BACK_BUFFER) != EGL_TRUE) {
      surface_error = LastFailure("angle_bind_tex_image");
      DestroySurface();
      return false;
    }
    return true;
  }

  void DestroySurface() {
    if (display == EGL_NO_DISPLAY) return;
    if (surface != EGL_NO_SURFACE) {
      egl_release_tex_image(display, surface, EGL_BACK_BUFFER);
      egl_make_current(display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                       EGL_NO_CONTEXT);
      egl_destroy_surface(display, surface);
      surface = EGL_NO_SURFACE;
    }
  }

  void Shutdown() {
    DestroySurface();
    if (display != EGL_NO_DISPLAY && context != EGL_NO_CONTEXT) {
      egl_destroy_context(display, context);
    }
    context = EGL_NO_CONTEXT;
    config = nullptr;
    if (display != EGL_NO_DISPLAY) egl_terminate(display);
    display = EGL_NO_DISPLAY;
    Unload();
  }

  void Unload() {
    if (gles_module != nullptr) FreeLibrary(gles_module);
    if (egl_module != nullptr) FreeLibrary(egl_module);
    egl_module = nullptr;
    gles_module = nullptr;
    egl_loaded_path.clear();
    gles_loaded_path.clear();
    egl_get_proc_address = nullptr;
    egl_get_platform_display = nullptr;
    egl_initialize = nullptr;
    egl_terminate = nullptr;
    egl_choose_config = nullptr;
    egl_bind_api = nullptr;
    egl_create_context = nullptr;
    egl_destroy_context = nullptr;
    egl_create_pbuffer = nullptr;
    egl_destroy_surface = nullptr;
    egl_make_current = nullptr;
    egl_bind_tex_image = nullptr;
    egl_release_tex_image = nullptr;
    egl_get_error = nullptr;
    gl_finish = nullptr;
    gl_get_string = nullptr;
  }
};

struct NativeSubtitleTrack final {
  std::string id;
  std::string title;
  std::string language;
  std::string format;
};

struct DescriptorLease final {
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
  ComPtr<ID3D11Texture2D> texture;
  HANDLE shared_handle = nullptr;

  ~DescriptorLease() {
    if (shared_handle != nullptr) CloseHandle(shared_handle);
  }
};

const mpv_node* NodeMapValue(const mpv_node& node, const char* key) {
  if ((node.format != MPV_FORMAT_NODE_MAP &&
       node.format != MPV_FORMAT_NODE_ARRAY) ||
      node.u.list == nullptr || key == nullptr) {
    return nullptr;
  }
  for (int index = 0; index < node.u.list->num; ++index) {
    const char* node_key = node.u.list->keys == nullptr
                               ? nullptr
                               : node.u.list->keys[index];
    if (node_key != nullptr && std::string(node_key) == key) {
      return &node.u.list->values[index];
    }
  }
  return nullptr;
}

std::optional<std::string> NodeString(const mpv_node* node) {
  if (node == nullptr) return std::nullopt;
  if (node->format == MPV_FORMAT_STRING || node->format == MPV_FORMAT_OSD_STRING) {
    return node->u.string == nullptr ? std::optional<std::string>()
                                     : std::optional(std::string(node->u.string));
  }
  if (node->format == MPV_FORMAT_INT64) {
    return std::to_string(node->u.int64);
  }
  if (node->format == MPV_FORMAT_DOUBLE && std::isfinite(node->u.double_)) {
    return DoubleString(node->u.double_);
  }
  return std::nullopt;
}

std::optional<double> ReadDouble(const MpvLibrary& mpv,
                                 mpv_handle* handle,
                                 const char* property) {
  double value = 0.0;
  if (handle == nullptr || mpv.get_property == nullptr ||
      mpv.get_property(handle, property, MPV_FORMAT_DOUBLE, &value) < 0 ||
      !std::isfinite(value)) {
    return std::nullopt;
  }
  return value;
}

std::optional<bool> ReadFlag(const MpvLibrary& mpv,
                             mpv_handle* handle,
                             const char* property) {
  int value = 0;
  if (handle == nullptr || mpv.get_property == nullptr ||
      mpv.get_property(handle, property, MPV_FORMAT_FLAG, &value) < 0) {
    return std::nullopt;
  }
  return value != 0;
}

std::optional<std::string> ReadString(const MpvLibrary& mpv,
                                      mpv_handle* handle,
                                      const char* property) {
  if (handle == nullptr || mpv.get_property_string == nullptr) {
    return std::nullopt;
  }
  char* value = mpv.get_property_string(handle, property);
  if (value == nullptr) return std::nullopt;
  std::string result(value);
  mpv.free(value);
  return result;
}

void* GetMpvProcAddress(void* context, const char* name) {
  return context == nullptr
             ? nullptr
             : static_cast<AngleLibrary*>(context)->GetProcAddress(name);
}

}  // namespace

struct AvacaWindowsPlayerSession::NativeState final {
  MpvLibrary mpv;
  AngleLibrary angle;
  mpv_handle* mpv_handle = nullptr;
  mpv_render_context* render_context = nullptr;

  ComPtr<ID3D11Device> d3d_device;
  ComPtr<ID3D11DeviceContext> d3d_context;
  ComPtr<ID3D11Texture2D> internal_texture;
  ComPtr<ID3D11RenderTargetView> internal_render_target;
  ComPtr<ID3D11Texture2D> external_texture;
  HANDLE internal_shared_handle = nullptr;
  HANDLE external_shared_handle = nullptr;
  std::mutex surface_mutex;
  std::atomic<int> desired_width{kDefaultWidth};
  std::atomic<int> desired_height{kDefaultHeight};
  int width = kDefaultWidth;
  int height = kDefaultHeight;

  D3D_FEATURE_LEVEL feature_level = D3D_FEATURE_LEVEL_11_0;
  std::string adapter_name = "unknown";
  unsigned long mpv_api_version = 0;

  bool initialized = false;
  bool closed = false;
  bool loaded = false;
  bool started = false;
  bool paused = true;
  bool buffering = false;
  bool completed = false;
  bool error = false;
  bool render_failed = false;
  bool fullscreen = false;
  bool window_style_saved = false;
  LONG_PTR saved_style = 0;
  LONG_PTR saved_ex_style = 0;
  WINDOWPLACEMENT saved_placement{sizeof(WINDOWPLACEMENT)};

  double position = 0.0;
  double duration = 0.0;
  double buffered_position = 0.0;
  double speed = 1.0;
  int64_t last_seek_generation = 0;
  int64_t pending_initial_position_ms = 0;
  std::optional<std::string> preferred_subtitle;
  std::optional<std::string> selected_subtitle;
  std::vector<NativeSubtitleTrack> subtitle_tracks;
  std::string phase = "idle";
  std::string last_event = "created";
  std::string last_error;
  std::chrono::steady_clock::time_point last_state_emit =
      std::chrono::steady_clock::now();
  std::atomic<bool> render_update_requested{true};
  int64_t sequence = 0;

  bool InitializeGraphics() {
    const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
        D3D_FEATURE_LEVEL_9_3,
    };
    const HRESULT device_result = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels,
        ARRAYSIZE(levels), D3D11_SDK_VERSION, d3d_device.GetAddressOf(),
        &feature_level, d3d_context.GetAddressOf());
    if (FAILED(device_result)) {
      last_error = "d3d11_hardware_device_" + HResultString(device_result);
      return false;
    }

    ComPtr<IDXGIDevice> dxgi_device;
    if (SUCCEEDED(d3d_device.As(&dxgi_device))) {
      ComPtr<IDXGIAdapter> adapter;
      if (SUCCEEDED(dxgi_device->GetAdapter(&adapter))) {
        DXGI_ADAPTER_DESC description{};
        if (SUCCEEDED(adapter->GetDesc(&description))) {
          const int required = WideCharToMultiByte(
              CP_UTF8, 0, description.Description, -1, nullptr, 0, nullptr,
              nullptr);
          if (required > 1) {
            std::string value(static_cast<size_t>(required), '\0');
            WideCharToMultiByte(CP_UTF8, 0, description.Description, -1,
                                value.data(), required, nullptr, nullptr);
            value.resize(static_cast<size_t>(required - 1));
            adapter_name = std::move(value);
          }
        }
      }
    }

    if (!angle.Load()) {
      last_error = angle.LastFailure("angle_load");
      return false;
    }
    if (!angle.InitializeDisplay()) {
      last_error = angle.LastFailure("angle_d3d11_display");
      return false;
    }
    if (!RecreateSurfaceResources(kDefaultWidth, kDefaultHeight)) {
      last_error = angle.LastFailure("angle_d3d11_shared_surface");
      return false;
    }
    return true;
  }

  bool CreateSharedTexture(int width_value,
                           int height_value,
                           ComPtr<ID3D11Texture2D>* texture,
                           ComPtr<ID3D11RenderTargetView>* render_target,
                           HANDLE* shared_handle) {
    if (texture == nullptr || shared_handle == nullptr || d3d_device == nullptr) {
      return false;
    }
    *shared_handle = nullptr;
    D3D11_TEXTURE2D_DESC description{};
    description.Width = static_cast<UINT>(width_value);
    description.Height = static_cast<UINT>(height_value);
    description.MipLevels = 1;
    description.ArraySize = 1;
    description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    description.CPUAccessFlags = 0;
    description.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
    if (FAILED(d3d_device->CreateTexture2D(&description, nullptr,
                                           texture->GetAddressOf()))) {
      return false;
    }
    if (render_target != nullptr &&
        FAILED(d3d_device->CreateRenderTargetView(
            texture->Get(), nullptr, render_target->GetAddressOf()))) {
      texture->Reset();
      return false;
    }
    ComPtr<IDXGIResource> resource;
    if (FAILED(texture->As(&resource)) ||
        FAILED(resource->GetSharedHandle(shared_handle)) ||
        *shared_handle == nullptr) {
      if (render_target != nullptr) render_target->Reset();
      texture->Reset();
      return false;
    }
    return true;
  }

  bool RecreateSurfaceResources(int width_value, int height_value) {
    const int next_width = std::clamp(width_value, kMinimumDimension,
                                      kMaximumDimension);
    const int next_height = std::clamp(height_value, kMinimumDimension,
                                       kMaximumDimension);
    std::lock_guard<std::mutex> lock(surface_mutex);
    angle.DestroySurface();
    internal_render_target.Reset();
    internal_texture.Reset();
    external_texture.Reset();
    if (internal_shared_handle != nullptr) {
      CloseHandle(internal_shared_handle);
      internal_shared_handle = nullptr;
    }
    if (external_shared_handle != nullptr) {
      CloseHandle(external_shared_handle);
      external_shared_handle = nullptr;
    }

    if (!CreateSharedTexture(next_width, next_height, &internal_texture,
                             &internal_render_target,
                             &internal_shared_handle) ||
        !CreateSharedTexture(next_width, next_height, &external_texture,
                             nullptr, &external_shared_handle) ||
        !angle.CreateSurface(internal_shared_handle, next_width, next_height)) {
      last_error = "angle_d3d11_shared_surface";
      return false;
    }
    width = next_width;
    height = next_height;
    const float black[4] = {0.f, 0.f, 0.f, 1.f};
    d3d_context->ClearRenderTargetView(internal_render_target.Get(), black);
    d3d_context->Flush();
    render_update_requested.store(true);
    return true;
  }

  void Destroy() {
    if (render_context != nullptr) {
      mpv.render_context_set_update_callback(render_context, nullptr, nullptr);
      mpv.render_context_free(render_context);
      render_context = nullptr;
    }
    if (mpv_handle != nullptr) {
      mpv.terminate_destroy(mpv_handle);
      mpv_handle = nullptr;
    }
    angle.Shutdown();
    std::lock_guard<std::mutex> lock(surface_mutex);
    internal_render_target.Reset();
    internal_texture.Reset();
    external_texture.Reset();
    if (internal_shared_handle != nullptr) CloseHandle(internal_shared_handle);
    if (external_shared_handle != nullptr) CloseHandle(external_shared_handle);
    internal_shared_handle = nullptr;
    external_shared_handle = nullptr;
    d3d_context.Reset();
    d3d_device.Reset();
    initialized = false;
  }
};

class AvacaWindowsPlayerSession::CommandQueue final {
 public:
  std::mutex mutex;
  std::condition_variable condition;
  std::deque<std::function<void()>> commands;
};

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::OperationResult::Success() {
  OperationResult result;
  result.ok = true;
  return result;
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::OperationResult::Success(EncodableValue value) {
  OperationResult result;
  result.ok = true;
  result.value = std::move(value);
  return result;
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::OperationResult::Failure(
    std::string error_code,
    std::string error_message) {
  OperationResult result;
  result.error_code = std::move(error_code);
  result.error_message = std::move(error_message);
  return result;
}

AvacaWindowsPlayerSession::AvacaWindowsPlayerSession(
    std::string session_id,
    flutter::TextureRegistrar* texture_registrar,
    void* native_window,
    EmitCallback emit_callback)
    : session_id_(std::move(session_id)),
      texture_registrar_(texture_registrar),
      native_window_(native_window),
      emit_callback_(std::move(emit_callback)) {}

AvacaWindowsPlayerSession::~AvacaWindowsPlayerSession() { Close(); }

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::Initialize() {
  std::lock_guard<std::mutex> lifecycle_lock(lifecycle_mutex_);
  if (worker_thread_.joinable()) {
    return native_state_ != nullptr && native_state_->initialized
               ? OperationResult::Success()
               : OperationResult::Failure(
                     "PLAYER_BACKEND_INITIALIZATION",
                     "The Windows player backend is unavailable.");
  }
  if (texture_registrar_ == nullptr) {
    return OperationResult::Failure(
        "PLAYER_BACKEND_INITIALIZATION",
        "The Windows player texture registrar is unavailable.");
  }
  command_queue_ = std::make_unique<CommandQueue>();
  stop_requested_.store(false);
  worker_thread_ = std::thread(&AvacaWindowsPlayerSession::WorkerLoop, this);
  const auto result = RunSync(
      [this]() { return InitializeOnWorker(); });
  if (result.ok) return result;

  RunSync([this]() { return CloseOnWorker(); });
  stop_requested_.store(true);
  WakeWorker();
  if (worker_thread_.joinable()) worker_thread_.join();
  command_queue_.reset();
  native_state_.reset();
  texture_id_ = -1;
  return result;
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::Open(const EncodableMap& request) {
  return RunSync([this, request]() { return OpenOnWorker(request); });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::Play() {
  return RunSync([this]() { return PlayOnWorker(); });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::Pause() {
  return RunSync([this]() { return PauseOnWorker(); });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::Seek(int64_t position_ms, int64_t generation) {
  return RunSync([this, position_ms, generation]() {
    return SeekOnWorker(position_ms, generation);
  });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::SetSpeed(double speed) {
  return RunSync([this, speed]() { return SetSpeedOnWorker(speed); });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::SelectSubtitle(const std::string* track_id) {
  const std::optional<std::string> selected =
      track_id == nullptr ? std::nullopt : std::optional(*track_id);
  return RunSync([this, selected]() {
    return SelectSubtitleOnWorker(
        selected ? &selected.value() : static_cast<const std::string*>(nullptr));
  });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::SetFullscreen(bool fullscreen) {
  return RunSync([this, fullscreen]() {
    return SetFullscreenOnWorker(fullscreen);
  });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::GetDiagnostics() {
  return RunSync([this]() { return GetDiagnosticsOnWorker(); });
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::Close() {
  std::lock_guard<std::mutex> lifecycle_lock(lifecycle_mutex_);
  if (!worker_thread_.joinable()) return OperationResult::Success();
  const auto result = RunSync([this]() { return CloseOnWorker(); });
  stop_requested_.store(true);
  WakeWorker();
  if (worker_thread_.joinable()) worker_thread_.join();
  command_queue_.reset();
  native_state_.reset();
  texture_id_ = -1;
  return result;
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::RunSync(
    std::function<OperationResult()> operation) {
  if (!command_queue_ || !worker_thread_.joinable()) {
    return OperationResult::Failure(
        "PLAYER_LIFECYCLE", "The Windows player session is not running.");
  }
  if (std::this_thread::get_id() == worker_thread_.get_id()) {
    return operation();
  }

  auto promise = std::make_shared<std::promise<OperationResult>>();
  auto future = promise->get_future();
  {
    std::lock_guard<std::mutex> lock(command_queue_->mutex);
    command_queue_->commands.emplace_back(
        [promise, operation = std::move(operation)]() mutable {
          try {
            promise->set_value(operation());
          } catch (...) {
            promise->set_value(OperationResult::Failure(
                "PLAYER_LIFECYCLE", "The native player operation failed."));
          }
        });
  }
  WakeWorker();
  return future.get();
}

void AvacaWindowsPlayerSession::WakeWorker() {
  if (command_queue_ != nullptr) command_queue_->condition.notify_one();
}

void AvacaWindowsPlayerSession::WorkerLoop() {
  while (!stop_requested_.load()) {
    std::vector<std::function<void()>> commands;
    {
      std::unique_lock<std::mutex> lock(command_queue_->mutex);
      if (command_queue_->commands.empty() && !stop_requested_.load()) {
        command_queue_->condition.wait_for(lock, std::chrono::milliseconds(16));
      }
      commands.reserve(command_queue_->commands.size());
      while (!command_queue_->commands.empty()) {
        commands.emplace_back(std::move(command_queue_->commands.front()));
        command_queue_->commands.pop_front();
      }
    }
    for (auto& command : commands) command();
    if (stop_requested_.load()) break;

    if (native_state_ == nullptr || !native_state_->initialized ||
        native_state_->closed || native_state_->mpv_handle == nullptr) {
      continue;
    }

    for (int event_count = 0; event_count < 8; ++event_count) {
      mpv_event* event = native_state_->mpv.wait_event(native_state_->mpv_handle,
                                                        0.0);
      if (event == nullptr || event->event_id == MPV_EVENT_NONE) break;
      ProcessMpvEvent(event);
    }

    if (native_state_->render_update_requested.load()) RenderFrame();

    const auto now = std::chrono::steady_clock::now();
    if (now - native_state_->last_state_emit >=
        std::chrono::milliseconds(250)) {
      RefreshStateFromMpv();
      EmitState();
      native_state_->last_state_emit = now;
    }
  }
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::InitializeOnWorker() {
  native_state_ = std::make_unique<NativeState>();
  NativeState& state = *native_state_;
  if (!state.InitializeGraphics()) {
    EmitError("backendInitialization", "playerErrorBackendInitialization",
              state.last_error.empty() ? "angle_d3d11_unavailable"
                                       : state.last_error.c_str(),
              false);
    return OperationResult::Failure(
        "PLAYER_BACKEND_INITIALIZATION",
        "The Windows GPU player backend could not be initialized: " +
            state.last_error);
  }
  if (!state.mpv.Load()) {
    state.last_error = "libmpv_library_or_symbol_missing";
    EmitError("backendInitialization", "playerErrorBackendInitialization",
              state.last_error.c_str(), false);
    return OperationResult::Failure(
        "PLAYER_BACKEND_INITIALIZATION",
        "The bundled libmpv runtime is unavailable.");
  }

  state.mpv_handle = state.mpv.create();
  if (state.mpv_handle == nullptr) {
    state.last_error = "mpv_create";
    EmitError("backendInitialization", "playerErrorBackendInitialization",
              state.last_error.c_str(), false);
    return OperationResult::Failure(
        "PLAYER_BACKEND_INITIALIZATION",
        "libmpv could not create a player instance.");
  }
  state.mpv_api_version = state.mpv.client_api_version();

  const auto set_option = [&state](const char* name, const char* value,
                                   bool required) {
    const int result = state.mpv.set_option_string(state.mpv_handle, name, value);
    if (result < 0 && required) {
      state.last_error = std::string("mpv_option_") + name;
      return false;
    }
    return true;
  };
  if (!set_option("config", "no", true) ||
      !set_option("terminal", "no", true) ||
      !set_option("vo", "libmpv", true) ||
      !set_option("ao", "wasapi", true) ||
      !set_option("hwdec", "auto-safe", true) ||
      !set_option("hwdec-codecs", "all", false) ||
      !set_option("keep-open", "yes", true) ||
      !set_option("idle", "yes", true) ||
      !set_option("msg-level", "all=error", false)) {
    EmitError("backendInitialization", "playerErrorBackendInitialization",
              state.last_error.c_str(), false);
    return OperationResult::Failure(
        "PLAYER_BACKEND_INITIALIZATION",
        "libmpv rejected the AVACA embedding options.");
  }
  if (state.mpv.initialize(state.mpv_handle) < 0) {
    state.last_error = "mpv_initialize";
    EmitError("backendInitialization", "playerErrorBackendInitialization",
              state.last_error.c_str(), false);
    return OperationResult::Failure(
        "PLAYER_BACKEND_INITIALIZATION", "libmpv could not initialize.");
  }

  mpv_opengl_init_params gl_params{};
  gl_params.get_proc_address = &GetMpvProcAddress;
  gl_params.get_proc_address_ctx = &state.angle;
  const char* api_type = MPV_RENDER_API_TYPE_OPENGL;
  mpv_render_param render_params[] = {
      {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(api_type)},
      {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_params},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  const int render_result = state.mpv.render_context_create(
      &state.render_context, state.mpv_handle, render_params);
  if (render_result < 0 || state.render_context == nullptr) {
    state.last_error = "mpv_render_context_create";
    EmitError("rendererFailure", "playerErrorRendererFailure",
              state.last_error.c_str(), false);
    return OperationResult::Failure(
        "PLAYER_RENDERER_FAILURE",
        "libmpv could not attach to the ANGLE GPU surface.");
  }
  state.mpv.render_context_set_update_callback(
      state.render_context, &AvacaWindowsPlayerSession::OnMpvRenderUpdate,
      this);

  const auto observe = [&state](const char* name, mpv_format format) {
    return state.mpv.observe_property(state.mpv_handle, 0, name, format) >= 0;
  };
  observe("time-pos", MPV_FORMAT_DOUBLE);
  observe("duration", MPV_FORMAT_DOUBLE);
  observe("pause", MPV_FORMAT_FLAG);
  observe("eof-reached", MPV_FORMAT_FLAG);
  observe("demuxer-cache-time", MPV_FORMAT_DOUBLE);
  observe("cache-buffering-state", MPV_FORMAT_FLAG);
  observe("track-list", MPV_FORMAT_NODE);
  observe("sid", MPV_FORMAT_STRING);
  state.mpv.request_event(state.mpv_handle, MPV_EVENT_FILE_LOADED, 1);
  state.mpv.request_event(state.mpv_handle, MPV_EVENT_END_FILE, 1);
  state.mpv.request_event(state.mpv_handle, MPV_EVENT_VIDEO_RECONFIG, 1);
  state.mpv.request_event(state.mpv_handle, MPV_EVENT_SHUTDOWN, 1);

  texture_variant_ = std::make_unique<flutter::TextureVariant>(
      std::in_place_type<flutter::GpuSurfaceTexture>,
      kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
      [this](size_t width, size_t height) {
        return ObtainDescriptor(width, height);
      });
  texture_id_ = texture_registrar_->RegisterTexture(texture_variant_.get());
  if (texture_id_ < 0) {
    state.last_error = "flutter_gpu_texture_registration";
    EmitError("rendererFailure", "playerErrorRendererFailure",
              state.last_error.c_str(), false);
    return OperationResult::Failure(
        "PLAYER_RENDERER_FAILURE", "Flutter rejected the GPU texture.");
  }

  state.initialized = true;
  state.phase = "idle";
  state.last_event = "initialized";
  EmitState();
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::OpenOnWorker(const EncodableMap& request) {
  if (native_state_ == nullptr || !native_state_->initialized) {
    return OperationResult::Failure(
        "PLAYER_LIFECYCLE", "The Windows player backend is not initialized.");
  }
  NativeState& state = *native_state_;
  const auto* source = MapMap(request, "source");
  if (source == nullptr) {
    EmitError("invalidSource", "playerErrorInvalidSource", "source_missing",
              false);
    return OperationResult::Failure("PLAYER_INVALID_SOURCE",
                                    "The player source is missing.");
  }
  const auto source_kind = MapString(*source, "kind");
  std::string target;
  const bool remote = source_kind && *source_kind == "remote";
  if (source_kind && *source_kind == "local") {
    target = MapString(*source, "path").value_or("");
  } else if (remote) {
    target = MapString(*source, "uri").value_or("");
  }
  if (target.empty() || (!source_kind) ||
      (*source_kind != "local" && *source_kind != "remote")) {
    EmitError("invalidSource", "playerErrorInvalidSource", "source_invalid",
              false);
    return OperationResult::Failure("PLAYER_INVALID_SOURCE",
                                    "The player source is invalid.");
  }

  std::string header_fields;
  if (const auto* headers = MapMap(*source, "headers"); headers != nullptr) {
    for (const auto& entry : *headers) {
      const auto* key = std::get_if<std::string>(&entry.first);
      const auto* value = std::get_if<std::string>(&entry.second);
      if (key == nullptr || value == nullptr || key->empty() ||
          key->find_first_of("\r\n") != std::string::npos ||
          value->find_first_of("\r\n") != std::string::npos) {
        EmitError("remoteRequestFailure", "playerErrorRemoteRequestFailure",
                  "http_header_invalid", true);
        return OperationResult::Failure(
            "PLAYER_REMOTE_REQUEST_FAILURE", "The HTTP headers are invalid.");
      }
      if (!header_fields.empty()) header_fields.push_back(',');
      header_fields += *key;
      header_fields += ": ";
      header_fields += *value;
    }
  }
  if (state.mpv.set_property_string(state.mpv_handle, "http-header-fields",
                                    header_fields.c_str()) < 0) {
    state.last_error = "http_header_fields";
    EmitError("remoteRequestFailure", "playerErrorRemoteRequestFailure",
              state.last_error.c_str(), true);
    return OperationResult::Failure(
        "PLAYER_REMOTE_REQUEST_FAILURE",
        "libmpv could not apply the HTTP request headers.");
  }

  const char* command[] = {"loadfile", target.c_str(), "replace", nullptr};
  const int command_result = state.mpv.command(state.mpv_handle, command);
  if (command_result < 0) {
    state.last_error = remote ? "mpv_loadfile_remote" : "mpv_loadfile_local";
    EmitError("mediaOpenFailed", "playerErrorMediaOpenFailed",
              state.last_error.c_str(), true);
    return OperationResult::Failure("PLAYER_MEDIA_OPEN_FAILED",
                                    "libmpv could not open the media source.");
  }

  state.loaded = false;
  state.started = false;
  state.paused = true;
  state.buffering = true;
  state.completed = false;
  state.error = false;
  state.render_failed = false;
  state.position = 0.0;
  state.duration = 0.0;
  state.buffered_position = 0.0;
  state.subtitle_tracks.clear();
  state.selected_subtitle.reset();
  state.pending_initial_position_ms = std::max<int64_t>(
      0, MapInt64(request, "initialPositionMs").value_or(0));
  state.preferred_subtitle = MapString(request, "preferredSubtitleTrackId");
  state.phase = "loading";
  state.last_event = "open";
  state.render_update_requested.store(true);
  EmitState("loading");
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::PlayOnWorker() {
  if (native_state_ == nullptr || !native_state_->initialized ||
      native_state_->mpv_handle == nullptr) {
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "The Windows player is not initialized.");
  }
  NativeState& state = *native_state_;
  if (state.mpv.set_property_string(state.mpv_handle, "pause", "no") < 0) {
    state.last_error = "mpv_pause_no";
    EmitError("lifecycleFailure", "playerErrorLifecycleFailure",
              state.last_error.c_str(), true);
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "libmpv could not start playback.");
  }
  state.started = true;
  state.paused = false;
  state.completed = false;
  state.last_event = "play";
  EmitState();
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::PauseOnWorker() {
  if (native_state_ == nullptr || !native_state_->initialized ||
      native_state_->mpv_handle == nullptr) {
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "The Windows player is not initialized.");
  }
  NativeState& state = *native_state_;
  if (state.mpv.set_property_string(state.mpv_handle, "pause", "yes") < 0) {
    state.last_error = "mpv_pause_yes";
    EmitError("lifecycleFailure", "playerErrorLifecycleFailure",
              state.last_error.c_str(), true);
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "libmpv could not pause playback.");
  }
  state.started = true;
  state.paused = true;
  state.last_event = "pause";
  EmitState();
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::SeekOnWorker(int64_t position_ms,
                                        int64_t generation) {
  if (native_state_ == nullptr || !native_state_->initialized ||
      native_state_->mpv_handle == nullptr) {
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "The Windows player is not initialized.");
  }
  NativeState& state = *native_state_;
  const double seconds =
      static_cast<double>(std::max<int64_t>(0, position_ms)) / 1000.0;
  const std::string seconds_string = DoubleString(seconds);
  const char* command[] = {"seek", seconds_string.c_str(), "absolute+exact",
                           nullptr};
  if (state.mpv.command(state.mpv_handle, command) < 0) {
    state.last_error = "mpv_seek";
    EmitError("seekFailure", "playerErrorSeekFailure", state.last_error.c_str(),
              true);
    return OperationResult::Failure("PLAYER_SEEK_FAILURE",
                                    "libmpv could not seek the media.");
  }
  state.started = true;
  state.last_seek_generation = generation;
  state.last_event = "seek";
  EmitState(nullptr, false, generation);
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::SetSpeedOnWorker(double speed) {
  if (native_state_ == nullptr || !native_state_->initialized ||
      native_state_->mpv_handle == nullptr) {
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "The Windows player is not initialized.");
  }
  NativeState& state = *native_state_;
  if (!std::isfinite(speed)) speed = 1.0;
  state.speed = std::clamp(speed, 0.5, 4.0);
  const std::string speed_string = DoubleString(state.speed);
  if (state.mpv.set_property_string(state.mpv_handle, "speed",
                                    speed_string.c_str()) < 0) {
    state.last_error = "mpv_speed";
    EmitError("lifecycleFailure", "playerErrorLifecycleFailure",
              state.last_error.c_str(), true);
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "libmpv could not change playback speed.");
  }
  state.last_event = "speed";
  EmitState();
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::SelectSubtitleOnWorker(const std::string* track_id) {
  if (native_state_ == nullptr || !native_state_->initialized ||
      native_state_->mpv_handle == nullptr) {
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "The Windows player is not initialized.");
  }
  NativeState& state = *native_state_;
  if (track_id != nullptr &&
      (track_id->empty() ||
       !std::all_of(track_id->begin(), track_id->end(),
                    [](unsigned char value) { return std::isdigit(value) != 0; }))) {
    EmitError("subtitleFailure", "playerErrorSubtitleFailure",
              "subtitle_track_id_invalid", true);
    return OperationResult::Failure("PLAYER_SUBTITLE_FAILURE",
                                    "The subtitle track id is invalid.");
  }
  const char* selected = track_id == nullptr ? "no" : track_id->c_str();
  if (state.mpv.set_property_string(state.mpv_handle, "sid", selected) < 0) {
    state.last_error = "mpv_sid";
    EmitError("subtitleFailure", "playerErrorSubtitleFailure",
              state.last_error.c_str(), true);
    return OperationResult::Failure("PLAYER_SUBTITLE_FAILURE",
                                    "libmpv could not select the subtitle.");
  }
  if (track_id == nullptr) {
    state.selected_subtitle.reset();
  } else {
    state.selected_subtitle = *track_id;
  }
  state.last_event = "subtitle";
  EmitState(nullptr, true);
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::SetFullscreenOnWorker(bool fullscreen) {
  if (native_state_ == nullptr || !native_state_->initialized) {
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "The Windows player is not initialized.");
  }
  NativeState& state = *native_state_;
  HWND window = reinterpret_cast<HWND>(native_window_);
  if (window == nullptr || !IsWindow(window)) {
    state.last_error = "fullscreen_window_unavailable";
    EmitError("lifecycleFailure", "playerErrorLifecycleFailure",
              state.last_error.c_str(), true);
    return OperationResult::Failure("PLAYER_LIFECYCLE",
                                    "The Windows player window is unavailable.");
  }
  if (state.fullscreen == fullscreen) {
    EmitState();
    return OperationResult::Success();
  }
  if (fullscreen) {
    state.saved_style = GetWindowLongPtrW(window, GWL_STYLE);
    state.saved_ex_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
    state.saved_placement.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(window, &state.saved_placement);
    state.window_style_saved = true;
    SetWindowLongPtrW(window, GWL_STYLE,
                      state.saved_style & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW));
    SetWindowLongPtrW(window, GWL_EXSTYLE,
                      state.saved_ex_style &
                          ~static_cast<LONG_PTR>(WS_EX_DLGMODALFRAME |
                                                 WS_EX_WINDOWEDGE |
                                                 WS_EX_CLIENTEDGE |
                                                 WS_EX_STATICEDGE));
    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info{sizeof(MONITORINFO)};
    if (monitor != nullptr && GetMonitorInfoW(monitor, &monitor_info)) {
      SetWindowPos(window, HWND_TOP, monitor_info.rcMonitor.left,
                   monitor_info.rcMonitor.top,
                   monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
                   monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    }
  } else if (state.window_style_saved) {
    SetWindowLongPtrW(window, GWL_STYLE, state.saved_style);
    SetWindowLongPtrW(window, GWL_EXSTYLE, state.saved_ex_style);
    SetWindowPlacement(window, &state.saved_placement);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }
  state.fullscreen = fullscreen;
  state.last_event = "fullscreen";
  EmitState();
  return OperationResult::Success();
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::GetDiagnosticsOnWorker() {
  EncodableMap values;
  const auto add_value = [&values](const char* key, std::string value) {
    values.emplace(EncodableValue(key), EncodableValue(std::move(value)));
  };
  if (native_state_ != nullptr) {
    const NativeState& state = *native_state_;
    add_value("backend", "libmpv");
    add_value("surface", "dxgiSharedHandle");
    add_value("renderPath", "angle_d3d11_shared_handle");
    add_value("renderer", "D3D11");
    add_value("surfaceType", "windowsExternalTexture");
    add_value("dartFrameCopy", "none");
    add_value("cpuReadback", "false");
    add_value("softwareFallback", "false");
    add_value("gpuOnly", "true");
    add_value("adapter", state.adapter_name);
    add_value("featureLevel", FeatureLevelString(state.feature_level));
    add_value("mpvLoadedPath", state.mpv.loaded_path);
    add_value("eglLoadedPath", state.angle.egl_loaded_path);
    add_value("glesLoadedPath", state.angle.gles_loaded_path);
    add_value("mpvApiVersion", std::to_string(state.mpv_api_version));
    add_value("hwdecCurrent",
              ReadString(state.mpv, state.mpv_handle, "hwdec-current")
                  .value_or("unknown"));
    add_value("lastError", state.last_error);
    add_value("phase", state.phase);
  } else {
    add_value("backend", "uninitialized");
    add_value("renderPath", "angle_d3d11_shared_handle");
    add_value("dartFrameCopy", "none");
  }
  EncodableMap result;
  result.emplace(EncodableValue("sessionId"), EncodableValue(session_id_));
  result.emplace(EncodableValue("lastEvent"),
                 EncodableValue(native_state_ == nullptr
                                    ? "uninitialized"
                                    : native_state_->last_event));
  result.emplace(EncodableValue("droppedEvents"), EncodableValue(int64_t{0}));
  result.emplace(EncodableValue("values"), EncodableValue(std::move(values)));
  return OperationResult::Success(EncodableValue(std::move(result)));
}

AvacaWindowsPlayerSession::OperationResult
AvacaWindowsPlayerSession::CloseOnWorker() {
  if (native_state_ == nullptr) {
    texture_id_ = -1;
    texture_variant_.reset();
    return OperationResult::Success();
  }
  NativeState& state = *native_state_;
  state.closed = true;
  state.render_update_requested.store(false);
  if (texture_id_ >= 0 && texture_registrar_ != nullptr) {
    struct UnregisterWait final {
      std::mutex mutex;
      std::condition_variable condition;
      bool complete = false;
    };
    auto wait = std::make_shared<UnregisterWait>();
    const int64_t unregister_id = texture_id_;
    texture_registrar_->UnregisterTexture(unregister_id, [wait]() {
      {
        std::lock_guard<std::mutex> lock(wait->mutex);
        wait->complete = true;
      }
      wait->condition.notify_one();
    });
    std::unique_lock<std::mutex> lock(wait->mutex);
    wait->condition.wait(lock, [&wait]() { return wait->complete; });
    texture_id_ = -1;
  }
  texture_variant_.reset();
  state.Destroy();
  return OperationResult::Success();
}

void AvacaWindowsPlayerSession::ProcessMpvEvent(const mpv_event* event) {
  NativeState& state = *native_state_;
  if (event == nullptr || event->event_id == MPV_EVENT_NONE) return;
  state.last_event = std::to_string(static_cast<int>(event->event_id));
  switch (event->event_id) {
    case MPV_EVENT_FILE_LOADED: {
      state.loaded = true;
      state.buffering = false;
      state.completed = false;
      state.error = false;
      state.phase = "ready";
      if (state.pending_initial_position_ms > 0) {
        const std::string seconds = DoubleString(
            static_cast<double>(state.pending_initial_position_ms) / 1000.0);
        const char* seek_command[] = {"seek", seconds.c_str(),
                                      "absolute+exact", nullptr};
        if (state.mpv.command(state.mpv_handle, seek_command) < 0) {
          state.last_error = "mpv_initial_seek";
          EmitError("seekFailure", "playerErrorSeekFailure",
                    state.last_error.c_str(), true);
        }
      }
      state.pending_initial_position_ms = 0;
      RefreshSubtitleTracks();
      if (state.preferred_subtitle) {
        const auto found = std::find_if(
            state.subtitle_tracks.begin(), state.subtitle_tracks.end(),
            [&state](const NativeSubtitleTrack& track) {
              return track.id == *state.preferred_subtitle;
            });
        if (found != state.subtitle_tracks.end()) {
          state.mpv.set_property_string(state.mpv_handle, "sid",
                                         found->id.c_str());
          state.selected_subtitle = found->id;
        }
      }
      RefreshStateFromMpv();
      EmitState();
      break;
    }
    case MPV_EVENT_END_FILE: {
      const auto* end_file = static_cast<const mpv_event_end_file*>(event->data);
      const int error = end_file == nullptr ? event->error : end_file->error;
      if (error != 0) {
        state.last_error = "mpv_end_file_" + std::to_string(error);
        const char* type = error == -16 ? "unsupportedMedia" : "mediaOpenFailed";
        const char* key = error == -16 ? "playerErrorUnsupportedMedia"
                                       : "playerErrorMediaOpenFailed";
        EmitError(type, key, state.last_error.c_str(), true);
      } else {
        state.completed = true;
        state.paused = true;
        state.buffering = false;
        state.phase = "completed";
        EmitState("completed");
      }
      break;
    }
    case MPV_EVENT_PROPERTY_CHANGE: {
      const auto* property =
          static_cast<const mpv_event_property*>(event->data);
      if (property != nullptr && property->name != nullptr &&
          std::string(property->name) == "track-list") {
        RefreshSubtitleTracks();
      }
      break;
    }
    case MPV_EVENT_VIDEO_RECONFIG:
      state.render_update_requested.store(true);
      break;
    case MPV_EVENT_SHUTDOWN:
      state.last_error = "mpv_shutdown";
      EmitError("lifecycleFailure", "playerErrorLifecycleFailure",
                state.last_error.c_str(), false);
      break;
    default:
      break;
  }
}

void AvacaWindowsPlayerSession::RefreshStateFromMpv() {
  if (native_state_ == nullptr || native_state_->mpv_handle == nullptr) return;
  NativeState& state = *native_state_;
  if (const auto value = ReadDouble(state.mpv, state.mpv_handle, "time-pos")) {
    state.position = std::max(0.0, *value);
  }
  if (const auto value = ReadDouble(state.mpv, state.mpv_handle, "duration")) {
    state.duration = std::max(0.0, *value);
  }
  if (const auto value = ReadFlag(state.mpv, state.mpv_handle, "pause")) {
    state.paused = *value;
  }
  if (const auto value = ReadFlag(state.mpv, state.mpv_handle, "eof-reached")) {
    state.completed = *value;
  }
  if (const auto value =
          ReadDouble(state.mpv, state.mpv_handle, "demuxer-cache-time")) {
    state.buffered_position = state.position + std::max(0.0, *value);
  } else {
    state.buffered_position = state.position;
  }
  if (state.duration > 0.0) {
    state.position = std::min(state.position, state.duration);
    state.buffered_position = std::min(state.buffered_position, state.duration);
  }
  if (const auto selected = ReadString(state.mpv, state.mpv_handle, "sid")) {
    if (*selected == "no" || selected->empty()) {
      state.selected_subtitle.reset();
    } else {
      state.selected_subtitle = *selected;
    }
  }
  if (state.error) {
    state.phase = "error";
  } else if (state.completed) {
    state.phase = "completed";
  } else if (!state.loaded) {
    state.phase = "idle";
  } else if (state.buffering) {
    state.phase = "buffering";
  } else if (!state.paused) {
    state.phase = "playing";
  } else if (!state.started) {
    state.phase = "ready";
  } else {
    state.phase = "paused";
  }
}

void AvacaWindowsPlayerSession::RefreshSubtitleTracks() {
  if (native_state_ == nullptr || native_state_->mpv_handle == nullptr) return;
  NativeState& state = *native_state_;
  mpv_node node{};
  if (state.mpv.get_property(state.mpv_handle, "track-list", MPV_FORMAT_NODE,
                             &node) < 0) {
    return;
  }
  std::vector<NativeSubtitleTrack> next_tracks;
  if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list != nullptr) {
    for (int index = 0; index < node.u.list->num; ++index) {
      const mpv_node& track = node.u.list->values[index];
      const auto type = NodeString(NodeMapValue(track, "type"));
      if (!type || *type != "sub") continue;
      const auto id = NodeString(NodeMapValue(track, "id"));
      if (!id || id->empty()) continue;
      NativeSubtitleTrack output;
      output.id = *id;
      output.title = NodeString(NodeMapValue(track, "title"))
                         .value_or(NodeString(NodeMapValue(track, "label"))
                                      .value_or(""));
      output.language = NodeString(NodeMapValue(track, "lang")).value_or("");
      const std::string codec = NodeString(NodeMapValue(track, "codec"))
                                    .value_or("");
      const std::string descriptor = output.title + " " + codec;
      if (descriptor.find("ass") != std::string::npos) {
        output.format = "ass";
      } else if (descriptor.find("ssa") != std::string::npos) {
        output.format = "ssa";
      } else {
        output.format = "other";
      }
      next_tracks.emplace_back(std::move(output));
    }
  }
  state.mpv.free_node_contents(&node);
  state.subtitle_tracks = std::move(next_tracks);
}

void AvacaWindowsPlayerSession::RenderFrame() {
  if (native_state_ == nullptr || !native_state_->initialized ||
      native_state_->render_context == nullptr) {
    return;
  }
  NativeState& state = *native_state_;
  const int desired_width = state.desired_width.load();
  const int desired_height = state.desired_height.load();
  if (desired_width != state.width || desired_height != state.height) {
    if (!state.RecreateSurfaceResources(desired_width, desired_height)) {
      if (!state.render_failed) {
        state.render_failed = true;
        EmitError("rendererFailure", "playerErrorRendererFailure",
                  "angle_d3d11_resize", true);
      }
      return;
    }
    state.render_failed = false;
  }

  bool rendered = false;
  {
    std::lock_guard<std::mutex> lock(state.surface_mutex);
    if (state.angle.surface == EGL_NO_SURFACE || state.internal_texture == nullptr ||
        state.external_texture == nullptr) {
      return;
    }
    const uint64_t flags =
        state.mpv.render_context_update(state.render_context);
    if ((flags & MPV_RENDER_UPDATE_FRAME) == 0) {
      state.render_update_requested.store(false);
      return;
    }
    mpv_opengl_fbo fbo{};
    fbo.fbo = 0;
    fbo.w = state.width;
    fbo.h = state.height;
    fbo.internal_format = 0;
    int flip_y = 1;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int result =
        state.mpv.render_context_render(state.render_context, params);
    if (result < 0) {
      state.last_error = "mpv_render";
      state.render_update_requested.store(false);
      if (!state.render_failed) {
        state.render_failed = true;
        EmitError("rendererFailure", "playerErrorRendererFailure",
                  state.last_error.c_str(), true);
      }
      return;
    }
    state.angle.gl_finish();
    state.d3d_context->CopyResource(state.external_texture.Get(),
                                    state.internal_texture.Get());
    state.d3d_context->Flush();
    state.mpv.render_context_report_swap(state.render_context);
    state.render_update_requested.store(false);
    rendered = true;
  }
  if (rendered && texture_id_ >= 0 && texture_registrar_ != nullptr &&
      !texture_registrar_->MarkTextureFrameAvailable(texture_id_)) {
    native_state_->last_error = "flutter_texture_mark_failed";
  }
}

void AvacaWindowsPlayerSession::EmitState(
    const char* phase_override,
    bool subtitle_selection_changed,
    std::optional<int64_t> seek_generation) {
  if (native_state_ == nullptr || !emit_callback_) return;
  NativeState& state = *native_state_;
  if (phase_override != nullptr) state.phase = phase_override;

  EncodableMap event;
  const auto add = [&event](const char* key, EncodableValue value) {
    event.emplace(EncodableValue(key), std::move(value));
  };
  EncodableValue tracks_value = EncodableValue(flutter::EncodableList{});
  auto& tracks = std::get<flutter::EncodableList>(tracks_value);
  for (const auto& track : state.subtitle_tracks) {
    EncodableMap item;
    item.emplace(EncodableValue("id"), EncodableValue(track.id));
    item.emplace(EncodableValue("title"), EncodableValue(track.title));
    item.emplace(EncodableValue("language"), EncodableValue(track.language));
    item.emplace(EncodableValue("format"), EncodableValue(track.format));
    tracks.emplace_back(EncodableValue(std::move(item)));
  }
  add("type", EncodableValue("state"));
  add("sessionId", EncodableValue(session_id_));
  add("sequence", EncodableValue(++state.sequence));
  add("phase", EncodableValue(state.phase));
  add("positionMs", EncodableValue(static_cast<int64_t>(
                                       std::max(0.0, state.position) * 1000.0)));
  add("durationMs", EncodableValue(static_cast<int64_t>(
                                       std::max(0.0, state.duration) * 1000.0)));
  add("bufferedPositionMs", EncodableValue(static_cast<int64_t>(
      std::max(0.0, state.buffered_position) * 1000.0)));
  add("playing", EncodableValue(!state.paused && !state.completed));
  add("buffering", EncodableValue(state.buffering));
  add("completed", EncodableValue(state.completed));
  add("tracks", EncodableValue(std::move(tracks_value)));
  if (state.selected_subtitle) {
    add("selectedSubtitleTrackId", EncodableValue(*state.selected_subtitle));
  } else {
    add("selectedSubtitleTrackId", EncodableValue());
  }
  add("subtitleSelectionChanged", EncodableValue(subtitle_selection_changed));
  add("speed", EncodableValue(state.speed));
  add("fullscreen", EncodableValue(state.fullscreen));
  if (seek_generation) {
    add("seekGeneration", EncodableValue(*seek_generation));
  } else {
    add("seekGeneration", EncodableValue());
  }
  emit_callback_(EncodableValue(std::move(event)));
}

void AvacaWindowsPlayerSession::EmitError(const char* error_type,
                                          const char* localized_message_key,
                                          const char* diagnostic_code,
                                          bool recoverable) {
  if (native_state_ == nullptr || !emit_callback_) return;
  NativeState& state = *native_state_;
  state.error = true;
  state.phase = "error";
  state.last_error = diagnostic_code == nullptr ? "native_error" : diagnostic_code;
  state.last_event = "error";
  EncodableMap event;
  event.emplace(EncodableValue("type"), EncodableValue("error"));
  event.emplace(EncodableValue("sessionId"), EncodableValue(session_id_));
  event.emplace(EncodableValue("sequence"), EncodableValue(++state.sequence));
  event.emplace(EncodableValue("errorType"),
                EncodableValue(error_type == nullptr ? "unknown" : error_type));
  event.emplace(EncodableValue("localizedMessageKey"),
                EncodableValue(localized_message_key == nullptr
                                   ? "playerErrorUnknown"
                                   : localized_message_key));
  event.emplace(EncodableValue("diagnosticCode"),
                EncodableValue(state.last_error));
  event.emplace(EncodableValue("recoverable"), EncodableValue(recoverable));
  emit_callback_(EncodableValue(std::move(event)));
  EmitState("error");
}

void AvacaWindowsPlayerSession::RequestRender() {
  if (native_state_ != nullptr) {
    native_state_->render_update_requested.store(true);
  }
}

const FlutterDesktopGpuSurfaceDescriptor*
AvacaWindowsPlayerSession::ObtainDescriptor(size_t width, size_t height) {
  if (native_state_ == nullptr || native_state_->closed) return nullptr;
  NativeState& state = *native_state_;
  state.desired_width.store(ClampDimension(width, state.width));
  state.desired_height.store(ClampDimension(height, state.height));
  auto lease = std::make_unique<DescriptorLease>();
  std::lock_guard<std::mutex> lock(state.surface_mutex);
  if (state.external_texture == nullptr || state.external_shared_handle == nullptr ||
      state.closed) {
    return nullptr;
  }
  HANDLE duplicated = nullptr;
  if (!DuplicateHandle(GetCurrentProcess(), state.external_shared_handle,
                       GetCurrentProcess(), &duplicated, 0, FALSE,
                       DUPLICATE_SAME_ACCESS)) {
    return nullptr;
  }
  lease->texture = state.external_texture;
  lease->shared_handle = duplicated;
  lease->descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  lease->descriptor.handle = duplicated;
  lease->descriptor.width = static_cast<size_t>(state.width);
  lease->descriptor.height = static_cast<size_t>(state.height);
  lease->descriptor.visible_width = static_cast<size_t>(state.width);
  lease->descriptor.visible_height = static_cast<size_t>(state.height);
  lease->descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
  lease->descriptor.release_callback = &AvacaWindowsPlayerSession::ReleaseDescriptor;
  lease->descriptor.release_context = lease.get();
  return &lease.release()->descriptor;
}

void AvacaWindowsPlayerSession::ReleaseDescriptor(void* release_context) {
  delete static_cast<DescriptorLease*>(release_context);
}

void AvacaWindowsPlayerSession::OnMpvRenderUpdate(void* callback_context) {
  if (callback_context == nullptr) return;
  static_cast<AvacaWindowsPlayerSession*>(callback_context)->RequestRender();
}

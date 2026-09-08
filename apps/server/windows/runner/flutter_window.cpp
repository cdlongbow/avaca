#include "flutter_window.h"

#include <windows.h>
#include <wincrypt.h>

#include <optional>
#include <map>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
      nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

flutter::EncodableList HashBytes(const BYTE* bytes, DWORD length) {
  flutter::EncodableList result;
  result.reserve(length);
  for (DWORD index = 0; index < length; ++index) {
    result.emplace_back(static_cast<int64_t>(bytes[index]));
  }
  return result;
}

const flutter::EncodableValue* MapValue(
    const flutter::EncodableMap& map,
    const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::optional<std::string> MapString(const flutter::EncodableMap& map,
                                     const char* key) {
  const auto* value = MapValue(map, key);
  if (value == nullptr || value->IsNull()) return std::nullopt;
  const auto* string = std::get_if<std::string>(value);
  return string == nullptr ? std::nullopt : std::optional(*string);
}

std::optional<int64_t> MapInt64(const flutter::EncodableMap& map,
                                const char* key) {
  const auto* value = MapValue(map, key);
  return value == nullptr ? std::nullopt : value->TryGetLongValue();
}

flutter::EncodableValue ListUserCertificates() {
  flutter::EncodableList certificates;
  HCERTSTORE store =
      CertOpenSystemStoreW(static_cast<HCRYPTPROV_LEGACY>(0), L"MY");
  if (store == nullptr) return flutter::EncodableValue(certificates);

  PCCERT_CONTEXT context = nullptr;
  while ((context = CertEnumCertificatesInStore(store, context)) != nullptr) {
    DWORD subject_length = CertGetNameStringW(
        context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr, nullptr, 0);
    if (subject_length == 0) continue;
    std::wstring subject(subject_length, L'\0');
    CertGetNameStringW(context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr,
                       subject.data(), subject_length);
    if (!subject.empty() && subject.back() == L'\0') subject.pop_back();

    BYTE sha256[32] = {};
    DWORD sha256_length = sizeof(sha256);
    if (!CryptHashCertificate(static_cast<HCRYPTPROV_LEGACY>(0), CALG_SHA_256, 0,
                               context->pbCertEncoded,
                               context->cbCertEncoded, sha256,
                               &sha256_length) ||
        sha256_length != sizeof(sha256)) {
      continue;
    }

    BYTE sha1[20] = {};
    DWORD sha1_length = sizeof(sha1);
    if (!CertGetCertificateContextProperty(context, CERT_HASH_PROP_ID, sha1,
                                           &sha1_length) ||
        sha1_length != sizeof(sha1)) {
      continue;
    }

    flutter::EncodableMap item;
    item[flutter::EncodableValue("subject")] =
        flutter::EncodableValue(ToUtf8(subject));
    item[flutter::EncodableValue("certPin")] =
        flutter::EncodableValue(HashBytes(sha256, sha256_length));
    item[flutter::EncodableValue("sha1Thumbprint")] =
        flutter::EncodableValue(HashBytes(sha1, sha1_length));
    certificates.emplace_back(item);
  }
  CertCloseStore(store, 0);
  return flutter::EncodableValue(certificates);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  certificate_store_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "avaca/server/certificate_store",
      &flutter::StandardMethodCodec::GetInstance());
  certificate_store_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "list") {
          result->Success(ListUserCertificates());
        } else {
         result->NotImplemented();
         }
       });
  discovery_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "avaca/server/discovery",
          &flutter::StandardMethodCodec::GetInstance());
  discovery_ = std::make_unique<avaca_remote_core::AvacaWindowsDnsSd>();
  discovery_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "start") {
          const auto* arguments = call.arguments();
          const auto* map = arguments == nullptr
                                ? nullptr
                                : std::get_if<flutter::EncodableMap>(arguments);
          const auto server_id = map == nullptr
                                     ? std::optional<std::string>()
                                     : MapString(*map, "serverId");
          const auto port = map == nullptr
                                ? std::optional<int64_t>()
                                : MapInt64(*map, "port");
          const auto cert_pin = map == nullptr
                                    ? std::optional<std::string>()
                                    : MapString(*map, "certPin");
          const auto nonce = map == nullptr
                                 ? std::optional<std::string>()
                                 : MapString(*map, "nonce");
          if (!server_id || server_id->empty() || !port || *port < 1 ||
              *port > 65535 || !cert_pin || cert_pin->empty() || !nonce ||
              nonce->empty()) {
            result->Error("INVALID_DISCOVERY", "Discovery metadata is invalid.");
            return;
          }
          const bool registered = discovery_->RegisterService(
              "AVACA-" + *server_id, static_cast<uint16_t>(*port),
              {{"v", "2"},
               {"serverId", *server_id},
               {"port", std::to_string(*port)},
               {"certPin", *cert_pin},
               {"nonce", *nonce}});
          if (!registered) {
            result->Error("DISCOVERY_START_FAILED",
                          "Windows DNS-SD registration failed.");
          } else {
            result->Success();
          }
          return;
        }
        if (call.method_name() == "stop") {
          if (discovery_) discovery_->UnregisterService();
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (discovery_) discovery_->UnregisterService();
  discovery_channel_.reset();
  certificate_store_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

#include "flutter_window.h"

#include <windows.h>
#include <wincrypt.h>
#include <ncrypt.h>

#include <algorithm>
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

DWORD g_last_certificate_error = ERROR_SUCCESS;
const char* g_last_certificate_step = "none";

void RememberCertificateError(const char* step) {
  g_last_certificate_error = GetLastError();
  g_last_certificate_step = step;
}

void RememberCertificateStatus(SECURITY_STATUS status, const char* step) {
  g_last_certificate_error = static_cast<DWORD>(status);
  g_last_certificate_step = step;
}

bool HasAccessiblePrivateKey(PCCERT_CONTEXT context) {
  HCRYPTPROV_OR_NCRYPT_KEY_HANDLE key_handle = 0;
  DWORD key_spec = 0;
  BOOL must_free_key = FALSE;
  if (!CryptAcquireCertificatePrivateKey(
          context,
          CRYPT_ACQUIRE_CACHE_FLAG | CRYPT_ACQUIRE_SILENT_FLAG |
              CRYPT_ACQUIRE_ALLOW_NCRYPT_KEY_FLAG,
          nullptr, &key_handle, &key_spec, &must_free_key)) {
    return false;
  }
  if (must_free_key) {
    if (key_spec == CERT_NCRYPT_KEY_SPEC) {
      NCryptFreeObject(key_handle);
    } else {
      CryptReleaseContext(static_cast<HCRYPTPROV>(key_handle), 0);
    }
  }
  return true;
}

std::optional<flutter::EncodableMap> CertificateMap(
    PCCERT_CONTEXT context) {
  // A leaf certificate without an accessible private key cannot be used by
  // MsQuic.  Do not expose it to the Dart pairing flow.
  if (!HasAccessiblePrivateKey(context)) {
    RememberCertificateError("acquire-private-key");
    return std::nullopt;
  }

  DWORD subject_length = CertGetNameStringW(
      context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr, nullptr, 0);
  if (subject_length == 0) {
    RememberCertificateError("read-subject");
    return std::nullopt;
  }
  std::wstring subject(subject_length, L'\0');
  CertGetNameStringW(context, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, nullptr,
                     subject.data(), subject_length);
  if (!subject.empty() && subject.back() == L'\0') subject.pop_back();
  if (subject.empty()) return std::nullopt;

  BYTE sha256[32] = {};
  DWORD sha256_length = sizeof(sha256);
  if (!CryptHashCertificate(static_cast<HCRYPTPROV_LEGACY>(0), CALG_SHA_256, 0,
                             context->pbCertEncoded, context->cbCertEncoded,
      sha256, &sha256_length) ||
      sha256_length != sizeof(sha256)) {
    RememberCertificateError("hash-sha256");
    return std::nullopt;
  }

  BYTE sha1[20] = {};
  DWORD sha1_length = sizeof(sha1);
  if (!CertGetCertificateContextProperty(context, CERT_HASH_PROP_ID, sha1,
                                         &sha1_length) ||
      sha1_length != sizeof(sha1)) {
    RememberCertificateError("read-sha1");
    return std::nullopt;
  }

  flutter::EncodableMap item;
  item[flutter::EncodableValue("subject")] =
      flutter::EncodableValue(ToUtf8(subject));
  item[flutter::EncodableValue("certPin")] =
      flutter::EncodableValue(HashBytes(sha256, sha256_length));
  item[flutter::EncodableValue("sha1Thumbprint")] =
      flutter::EncodableValue(HashBytes(sha1, sha1_length));
  item[flutter::EncodableValue("hasPrivateKey")] =
      flutter::EncodableValue(true);
  return item;
}

flutter::EncodableValue ListUserCertificates() {
  flutter::EncodableList certificates;
  HCERTSTORE store =
      CertOpenSystemStoreW(static_cast<HCRYPTPROV_LEGACY>(0), L"MY");
  if (store == nullptr) return flutter::EncodableValue(certificates);

  PCCERT_CONTEXT context = nullptr;
  while ((context = CertEnumCertificatesInStore(store, context)) != nullptr) {
    const auto item = CertificateMap(context);
    if (item.has_value()) certificates.emplace_back(*item);
  }
  CertCloseStore(store, 0);
  return flutter::EncodableValue(certificates);
}

std::optional<flutter::EncodableMap> CreateServerCertificate() {
  g_last_certificate_error = ERROR_SUCCESS;
  g_last_certificate_step = "start";
  constexpr wchar_t kContainerName[] = L"AVACA Server QUIC";
  constexpr wchar_t kProviderName[] = MS_KEY_STORAGE_PROVIDER;

  NCRYPT_PROV_HANDLE provider = 0;
  const auto provider_status =
      NCryptOpenStorageProvider(&provider, kProviderName, 0);
  if (provider_status != ERROR_SUCCESS) {
    RememberCertificateStatus(provider_status, "open-storage-provider");
    return std::nullopt;
  }

  NCRYPT_KEY_HANDLE key = 0;
  // NCrypt uses zero for a native CNG key. CERT_NCRYPT_KEY_SPEC belongs in
  // CRYPT_KEY_PROV_INFO below, not in the NCrypt open/create calls.
  auto key_status = NCryptOpenKey(provider, &key, kContainerName, 0, 0);
  if (key_status != ERROR_SUCCESS) {
    g_last_certificate_step = "create-key";
    key_status = NCryptCreatePersistedKey(
        provider, &key, BCRYPT_RSA_ALGORITHM, kContainerName, 0, 0);
    if (key_status == ERROR_SUCCESS) {
      DWORD requested_length = 2048;
      key_status = NCryptSetProperty(
          key, NCRYPT_LENGTH_PROPERTY,
          reinterpret_cast<PBYTE>(&requested_length),
          sizeof(requested_length), 0);
      if (key_status == ERROR_SUCCESS) {
        key_status = NCryptFinalizeKey(key, 0);
      }
    } else if (key_status == NTE_EXISTS) {
      g_last_certificate_step = "open-existing-key";
      key_status = NCryptOpenKey(provider, &key, kContainerName, 0, 0);
    }
    if (key_status != ERROR_SUCCESS) {
      RememberCertificateStatus(key_status, g_last_certificate_step);
      if (key != 0) NCryptFreeObject(key);
      NCryptFreeObject(provider);
      return std::nullopt;
    }
  }

  DWORD key_length = 0;
  DWORD key_length_size = sizeof(key_length);
  key_status = NCryptGetProperty(
      key, NCRYPT_LENGTH_PROPERTY, reinterpret_cast<PBYTE>(&key_length),
      sizeof(key_length), &key_length_size, 0);
  if (key_status != ERROR_SUCCESS ||
      key_length < 2048) {
    if (key_status == ERROR_SUCCESS) key_status = NTE_BAD_KEY;
    RememberCertificateStatus(key_status, "read-key-length");
    NCryptFreeObject(key);
    NCryptFreeObject(provider);
    return std::nullopt;
  }

  constexpr wchar_t kSubjectName[] = L"CN=AVACA Server QUIC";
  DWORD subject_size = 0;
  if (!CertStrToNameW(X509_ASN_ENCODING, kSubjectName, CERT_X500_NAME_STR,
                      nullptr, nullptr, &subject_size, nullptr)) {
    RememberCertificateError("encode-subject-size");
    NCryptFreeObject(key);
    NCryptFreeObject(provider);
    return std::nullopt;
  }
  std::vector<BYTE> subject_bytes(subject_size);
  if (!CertStrToNameW(X509_ASN_ENCODING, kSubjectName, CERT_X500_NAME_STR,
                      nullptr, subject_bytes.data(), &subject_size, nullptr)) {
    RememberCertificateError("encode-subject");
    NCryptFreeObject(key);
    NCryptFreeObject(provider);
    return std::nullopt;
  }

  CERT_NAME_BLOB subject_blob = {};
  subject_blob.cbData = subject_size;
  subject_blob.pbData = subject_bytes.data();

  CRYPT_KEY_PROV_INFO key_info = {};
  key_info.pwszContainerName = const_cast<LPWSTR>(kContainerName);
  key_info.pwszProvName = const_cast<LPWSTR>(kProviderName);
  // For a CNG provider dwProvType and dwLegacyKeySpec are both zero. The
  // CERT_NCRYPT_KEY_SPEC value is returned by CryptAcquireCertificatePrivateKey;
  // it must not be written into CRYPT_KEY_PROV_INFO.dwKeySpec here.
  key_info.dwKeySpec = 0;

  CRYPT_ALGORITHM_IDENTIFIER signature_algorithm = {};
  signature_algorithm.pszObjId = const_cast<LPSTR>(szOID_RSA_SHA256RSA);

  LPBYTE encoded_eku = nullptr;
  DWORD encoded_eku_size = 0;
  LPSTR server_auth_oid = const_cast<LPSTR>(szOID_PKIX_KP_SERVER_AUTH);
  CERT_ENHKEY_USAGE eku = {};
  eku.cUsageIdentifier = 1;
  eku.rgpszUsageIdentifier = &server_auth_oid;
  CERT_EXTENSION eku_extension = {};
  CERT_EXTENSIONS extensions = {};
  const bool has_eku = CryptEncodeObjectEx(
      X509_ASN_ENCODING, X509_ENHANCED_KEY_USAGE, &eku,
      CRYPT_ENCODE_ALLOC_FLAG, nullptr, &encoded_eku, &encoded_eku_size) !=
      FALSE;
  if (has_eku) {
    eku_extension.pszObjId = const_cast<LPSTR>(szOID_ENHANCED_KEY_USAGE);
    eku_extension.fCritical = TRUE;
    eku_extension.Value.cbData = encoded_eku_size;
    eku_extension.Value.pbData = encoded_eku;
    extensions.cExtension = 1;
    extensions.rgExtension = &eku_extension;
  }

  SYSTEMTIME not_before = {};
  SYSTEMTIME not_after = {};
  GetSystemTime(&not_before);
  not_after = not_before;
  not_after.wYear = static_cast<WORD>(
      std::min<int>(9999, static_cast<int>(not_after.wYear) + 5));

  PCCERT_CONTEXT certificate = CertCreateSelfSignCertificate(
      key, &subject_blob, 0, &key_info, &signature_algorithm,
      &not_before, &not_after, has_eku ? &extensions : nullptr);
  if (certificate == nullptr) RememberCertificateError("create-self-signed");
  if (encoded_eku != nullptr) LocalFree(encoded_eku);
  if (certificate == nullptr) {
    NCryptFreeObject(key);
    NCryptFreeObject(provider);
    return std::nullopt;
  }

  HCERTSTORE store =
      CertOpenSystemStoreW(static_cast<HCRYPTPROV_LEGACY>(0), L"MY");
  const bool stored = store != nullptr &&
                      CertAddCertificateContextToStore(
                          store, certificate, CERT_STORE_ADD_REPLACE_EXISTING,
                          nullptr) != FALSE;
  if (!stored) {
    if (store == nullptr) {
      g_last_certificate_error = ERROR_OPEN_FAILED;
      g_last_certificate_step = "open-certificate-store";
    } else {
      RememberCertificateError("add-certificate-to-store");
    }
  }
  std::optional<flutter::EncodableMap> item;
  if (stored) {
    item = CertificateMap(certificate);
    if (!item.has_value() && g_last_certificate_error == ERROR_SUCCESS) {
      g_last_certificate_error = ERROR_INVALID_DATA;
      g_last_certificate_step = "read-created-certificate";
    }
  }
  if (store != nullptr) CertCloseStore(store, 0);
  CertFreeCertificateContext(certificate);
  NCryptFreeObject(key);
  NCryptFreeObject(provider);
  return item;
}

std::optional<flutter::EncodableMap> EnsureServerCertificate() {
  const auto listed = ListUserCertificates();
  const auto* certificates = std::get_if<flutter::EncodableList>(&listed);
  if (certificates != nullptr) {
    for (const auto& value : *certificates) {
      const auto* item = std::get_if<flutter::EncodableMap>(&value);
      if (item == nullptr) continue;
      const auto subject = MapString(*item, "subject");
      if (subject.has_value() && *subject == "AVACA Server QUIC") {
        return *item;
      }
    }
  }
  return CreateServerCertificate();
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
        } else if (call.method_name() == "ensure") {
          const auto certificate = EnsureServerCertificate();
          if (!certificate.has_value()) {
            result->Error(
                "CERTIFICATE_CREATE_FAILED",
                "Unable to create the AVACA Server certificate in the current user store (Win32 error " +
                    std::to_string(g_last_certificate_error) + ", step " +
                    g_last_certificate_step + ").");
            return;
          }
          result->Success(flutter::EncodableValue(*certificate));
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

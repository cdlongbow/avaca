#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "include/avaca_remote_core/avaca_windows_discovery.h"

#include <windows.h>
#include <windns.h>

#include <algorithm>
#include <condition_variable>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace avaca_remote_core {
namespace {

constexpr char kDefaultServiceType[] = "_avaca-remote._udp";

std::wstring ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string ToUtf8(const wchar_t* value) {
  if (value == nullptr || *value == L'\0') return {};
  const int size = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string result(static_cast<size_t>(size), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1,
                          result.data(), size, nullptr, nullptr) <= 0) {
    return {};
  }
  result.resize(static_cast<size_t>(size - 1));
  return result;
}

std::wstring LocalDnsHostName() {
  DWORD length = 0;
  GetComputerNameExW(ComputerNamePhysicalDnsFullyQualified, nullptr, &length);
  std::vector<wchar_t> buffer(static_cast<size_t>(length) + 1);
  if (GetComputerNameExW(ComputerNamePhysicalDnsFullyQualified, buffer.data(),
                         &length) && length > 0) {
    std::wstring value(buffer.data(), length);
    if (value.find(L'.') == std::wstring::npos) value += L".local";
    if (value.back() != L'.') value += L'.';
    return value;
  }
  return L"localhost.local.";
}

bool IsPendingStatus(DWORD status) {
  return status == ERROR_SUCCESS || status == ERROR_IO_PENDING;
}

}  // namespace

struct AvacaWindowsDnsSd::Impl {
  static VOID WINAPI BrowseCallback(DWORD status,
                                    PVOID context,
                                    PDNS_RECORD records) {
    auto* impl = static_cast<Impl*>(context);
    if (records != nullptr) {
      if (impl != nullptr && status == ERROR_SUCCESS) {
        for (auto* record = records; record != nullptr;
             record = record->pNext) {
          if (record->wType != DNS_TYPE_PTR ||
              record->Data.PTR.pNameHost == nullptr) {
            continue;
          }
          impl->Resolve(record->Data.PTR.pNameHost);
        }
      }
      DnsRecordListFree(records, DnsFreeRecordList);
    }
  }

  static VOID WINAPI ResolveCallback(DWORD status,
                                     PVOID context,
                                     PDNS_SERVICE_INSTANCE instance) {
    auto* impl = static_cast<Impl*>(context);
    if (impl == nullptr) return;
    {
      std::lock_guard<std::mutex> lock(impl->mutex);
      ++impl->active_callbacks;
    }
    CandidateCallback callback;
    AvacaWindowsDiscoveryCandidate candidate;
    if (status == ERROR_SUCCESS && instance != nullptr) {
      candidate.host = ToUtf8(instance->pszHostName);
      candidate.port = instance->wPort;
      for (DWORD index = 0; index < instance->dwPropertyCount; ++index) {
        if (instance->keys == nullptr || instance->values == nullptr ||
            instance->keys[index] == nullptr ||
            instance->values[index] == nullptr) {
          continue;
        }
        candidate.txt.emplace(ToUtf8(instance->keys[index]),
                              ToUtf8(instance->values[index]));
      }
    }
    {
      std::lock_guard<std::mutex> lock(impl->mutex);
      if (impl->browsing) callback = impl->callback;
    }
    // Resolve callbacks are the ownership boundary for the request storage.
    // Mark the DNS request complete before invoking user code.  The callback
    // guard below keeps the context and RR-derived strings alive if another
    // thread stops browsing while the candidate is being consumed.
    impl->ResolveFinished();
    if (callback && !candidate.host.empty() && candidate.port != 0) {
      const auto previous_callback_impl = callback_impl;
      callback_impl = impl;
      try {
        callback(std::move(candidate));
      } catch (...) {
        // A native DNS-SD callback must never allow a Dart/plugin exception
        // to cross the Windows callback ABI.
      }
      callback_impl = previous_callback_impl;
    }
    {
      std::lock_guard<std::mutex> lock(impl->mutex);
      if (impl->active_callbacks != 0) --impl->active_callbacks;
      impl->condition.notify_all();
    }
    impl->FinishDeferredCleanup();
  }

  static VOID WINAPI RegisterCallback(DWORD status,
                                      PVOID context,
                                      PDNS_SERVICE_INSTANCE instance) {
    // Registration is acknowledged synchronously by RegisterService.  The
    // callback is intentionally empty, but it keeps the DNS-SD request valid
    // for Windows versions which report the final registration asynchronously.
    (void)status;
    (void)context;
    (void)instance;
  }

  void Resolve(const wchar_t* query_name) {
    if (query_name == nullptr || *query_name == L'\0') return;
    std::unique_ptr<std::wstring> name =
        std::make_unique<std::wstring>(query_name);
    auto cancel = std::make_unique<DNS_SERVICE_CANCEL>();
    *cancel = {};
    DNS_SERVICE_RESOLVE_REQUEST request = {};
    request.Version = DNS_QUERY_REQUEST_VERSION1;
    request.QueryName = name->data();
    request.pResolveCompletionCallback = &ResolveCallback;
    request.pQueryContext = this;
    DNS_SERVICE_CANCEL* cancel_handle = cancel.get();
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (!browsing) return;
      resolve_names.push_back(std::move(name));
      resolve_cancels.push_back(std::move(cancel));
      ++resolve_starting;
      ++active_resolves;
    }
    const auto status = DnsServiceResolve(&request, cancel_handle);
    if (!IsPendingStatus(status)) {
      ResolveFinished();
    }
    bool finish_deferred_cleanup = false;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (resolve_starting != 0) --resolve_starting;
      condition.notify_all();
      finish_deferred_cleanup = deferred_cleanup && resolve_starting == 0 &&
                                active_resolves == 0 && active_callbacks == 0;
    }
    if (finish_deferred_cleanup) FinishDeferredCleanup();
  }

  void ResolveFinished() {
    std::lock_guard<std::mutex> lock(mutex);
    if (active_resolves != 0) --active_resolves;
    condition.notify_all();
  }

  void CancelOutstanding() {
    DnsServiceBrowseCancel(&browse_cancel);
    std::vector<DNS_SERVICE_CANCEL*> resolve_cancel_handles;
    {
      std::lock_guard<std::mutex> lock(mutex);
      resolve_cancel_handles.reserve(resolve_cancels.size());
      for (const auto& cancel : resolve_cancels) {
        if (cancel) resolve_cancel_handles.push_back(cancel.get());
      }
    }
    for (auto* cancel : resolve_cancel_handles) {
      DnsServiceResolveCancel(cancel);
    }
  }

  void FinishDeferredCleanup() {
    bool cleanup = false;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (deferred_cleanup && resolve_starting == 0 &&
          active_resolves == 0 && active_callbacks == 0) {
        deferred_cleanup = false;
        cleanup = true;
      }
    }
    if (!cleanup) return;
    std::lock_guard<std::mutex> lock(mutex);
    resolve_cancels.clear();
    resolve_names.clear();
    callback = nullptr;
    condition.notify_all();
  }

  std::mutex mutex;
  std::condition_variable condition;
  static inline thread_local Impl* callback_impl = nullptr;
  bool browsing = false;
  bool deferred_cleanup = false;
  size_t resolve_starting = 0;
  size_t active_resolves = 0;
  size_t active_callbacks = 0;
  CandidateCallback callback;
  DNS_SERVICE_CANCEL browse_cancel = {};
  std::vector<std::unique_ptr<DNS_SERVICE_CANCEL>> resolve_cancels;
  std::vector<std::unique_ptr<std::wstring>> resolve_names;

  PDNS_SERVICE_INSTANCE registered_instance = nullptr;
  DNS_SERVICE_REGISTER_REQUEST register_request = {};
  DNS_SERVICE_CANCEL register_cancel = {};
  bool registered = false;
};

AvacaWindowsDnsSd::AvacaWindowsDnsSd() : impl_(std::make_unique<Impl>()) {}

AvacaWindowsDnsSd::~AvacaWindowsDnsSd() {
  UnregisterService();
  StopBrowsing();
}

bool AvacaWindowsDnsSd::StartBrowsing(const std::string& service_type,
                                      CandidateCallback callback) {
  StopBrowsing();
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (impl_->deferred_cleanup) return false;
  }
  const auto query = ToWide(service_type.empty() ? kDefaultServiceType
                                                  : service_type);
  if (query.empty() || !callback) return false;
  {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->callback = std::move(callback);
    impl_->browsing = true;
    impl_->browse_cancel = {};
  }
  DNS_SERVICE_BROWSE_REQUEST request = {};
  request.Version = DNS_QUERY_REQUEST_VERSION1;
  request.QueryName = query.c_str();
  request.pBrowseCallback = &Impl::BrowseCallback;
  request.pQueryContext = impl_.get();
  const auto status = DnsServiceBrowse(&request, &impl_->browse_cancel);
  if (!IsPendingStatus(status)) {
    StopBrowsing();
    return false;
  }
  return true;
}

void AvacaWindowsDnsSd::StopBrowsing() {
  if (!impl_) return;
  bool defer_cleanup = false;
  {
    std::unique_lock<std::mutex> lock(impl_->mutex);
    if (!impl_->browsing && impl_->resolve_starting == 0 &&
        impl_->active_resolves == 0 && impl_->active_callbacks == 0 &&
        !impl_->deferred_cleanup) {
      return;
    }
    impl_->browsing = false;
    if (Impl::callback_impl == impl_.get()) {
      // A DNS-SD implementation may invoke ResolveCallback before
      // DnsServiceResolve returns.  Do not wait on the current callback's
      // resolve-start marker; the callback will finish cleanup after the API
      // returns and all late callbacks have left the ABI boundary.
      impl_->deferred_cleanup = true;
      defer_cleanup = true;
    } else {
      impl_->condition.wait(lock,
                           [this]() { return impl_->resolve_starting == 0; });
    }
  }
  impl_->CancelOutstanding();
  if (defer_cleanup) return;
  std::unique_lock<std::mutex> lock(impl_->mutex);
  impl_->condition.wait(lock,
                       [this]() {
                         return impl_->active_resolves == 0 &&
                                impl_->active_callbacks == 0;
                       });
  impl_->resolve_cancels.clear();
  impl_->resolve_names.clear();
  impl_->callback = nullptr;
}

bool AvacaWindowsDnsSd::RegisterService(
    const std::string& instance_name,
    uint16_t port,
    const std::map<std::string, std::string>& txt) {
  UnregisterService();
  if (instance_name.empty() || port == 0 || txt.empty()) return false;
  const auto service_name = ToWide(kDefaultServiceType);
  const auto instance = ToWide(instance_name);
  const auto host = LocalDnsHostName();
  if (service_name.empty() || instance.empty() || host.empty()) return false;

  std::vector<std::wstring> keys;
  std::vector<std::wstring> values;
  std::vector<PCWSTR> key_pointers;
  std::vector<PCWSTR> value_pointers;
  keys.reserve(txt.size());
  values.reserve(txt.size());
  key_pointers.reserve(txt.size());
  value_pointers.reserve(txt.size());
  for (const auto& entry : txt) {
    keys.push_back(ToWide(entry.first));
    values.push_back(ToWide(entry.second));
  }
  for (size_t index = 0; index < keys.size(); ++index) {
    if (keys[index].empty() || values[index].empty()) return false;
    key_pointers.push_back(keys[index].c_str());
    value_pointers.push_back(values[index].c_str());
  }

  impl_->registered_instance = DnsServiceConstructInstance(
      service_name.c_str(), host.c_str(), nullptr, nullptr, port, 0, 0,
      static_cast<DWORD>(key_pointers.size()), key_pointers.data(),
      value_pointers.data());
  if (impl_->registered_instance == nullptr) return false;
  impl_->register_request = {};
  impl_->register_request.Version = DNS_QUERY_REQUEST_VERSION1;
  impl_->register_request.pServiceInstance = impl_->registered_instance;
  impl_->register_request.pRegisterCompletionCallback = &Impl::RegisterCallback;
  impl_->register_request.pQueryContext = impl_.get();
  impl_->register_request.unicastEnabled = FALSE;
  impl_->register_cancel = {};
  const auto status = DnsServiceRegister(&impl_->register_request,
                                         &impl_->register_cancel);
  if (!IsPendingStatus(status)) {
    DnsServiceFreeInstance(impl_->registered_instance);
    impl_->registered_instance = nullptr;
    return false;
  }
  impl_->registered = true;
  return true;
}

void AvacaWindowsDnsSd::UnregisterService() {
  if (!impl_ || !impl_->registered_instance) return;
  if (impl_->registered) {
    DnsServiceDeRegister(&impl_->register_request, &impl_->register_cancel);
    DnsServiceRegisterCancel(&impl_->register_cancel);
  }
  DnsServiceFreeInstance(impl_->registered_instance);
  impl_->registered_instance = nullptr;
  impl_->registered = false;
}

}  // namespace avaca_remote_core

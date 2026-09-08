#ifndef AVACA_WINDOWS_DISCOVERY_H_
#define AVACA_WINDOWS_DISCOVERY_H_

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <string>

namespace avaca_remote_core {

struct AvacaWindowsDiscoveryCandidate {
  std::string host;
  uint16_t port = 0;
  std::map<std::string, std::string> txt;
};

// Windows DNS-SD boundary shared by the Server registration path and the
// AVACA client browse path.  The TXT payload deliberately contains only
// candidate metadata; pairing secrets never cross this boundary.
class AvacaWindowsDnsSd final {
 public:
  using CandidateCallback =
      std::function<void(AvacaWindowsDiscoveryCandidate candidate)>;

  AvacaWindowsDnsSd();
  ~AvacaWindowsDnsSd();

  AvacaWindowsDnsSd(const AvacaWindowsDnsSd&) = delete;
  AvacaWindowsDnsSd& operator=(const AvacaWindowsDnsSd&) = delete;

  bool StartBrowsing(const std::string& service_type,
                     CandidateCallback callback);
  void StopBrowsing();

  bool RegisterService(const std::string& instance_name,
                       uint16_t port,
                       const std::map<std::string, std::string>& txt);
  void UnregisterService();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace avaca_remote_core

#endif  // AVACA_WINDOWS_DISCOVERY_H_

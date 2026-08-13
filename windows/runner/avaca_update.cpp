#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <chrono>
#include <cwctype>
#include <filesystem>
#include <cwchar>
#include <iterator>
#include <string>
#include <system_error>
#include <thread>
#include <vector>

namespace {

namespace fs = std::filesystem;

struct Options {
  fs::path install_root;
  fs::path stage_root;
  fs::path startup_marker;
  DWORD parent_pid = 0;
};

std::wstring Lowercase(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t character) {
                   return static_cast<wchar_t>(std::towlower(character));
                 });
  return value;
}

std::wstring Win32Error(DWORD error) {
  wchar_t buffer[256] = {};
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr,
      error, 0, buffer, static_cast<DWORD>(std::size(buffer)), nullptr);
  if (length == 0) {
    return L"Windows error " + std::to_wstring(error);
  }
  std::wstring message(buffer, length);
  while (!message.empty() &&
         (message.back() == L'\r' || message.back() == L'\n')) {
    message.pop_back();
  }
  return message;
}

void Log(const std::wstring& message) {
  wchar_t temp_path[MAX_PATH] = {};
  const DWORD length = GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length >= MAX_PATH) return;

  std::wstring log_path(temp_path, length);
  log_path += L"avaca-update.log";
  HANDLE file = CreateFileW(log_path.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;

  SYSTEMTIME now;
  GetLocalTime(&now);
  const std::wstring line =
      L"[" + std::to_wstring(now.wHour) + L":" +
      std::to_wstring(now.wMinute) + L":" + std::to_wstring(now.wSecond) +
      L"] " + message + L"\r\n";
  DWORD written = 0;
  WriteFile(file, line.data(),
            static_cast<DWORD>(line.size() * sizeof(wchar_t)), &written,
            nullptr);
  CloseHandle(file);
}

int Fail(const std::wstring& message) {
  Log(L"ERROR: " + message);
  return 1;
}

fs::path AbsolutePath(const std::wstring& value) {
  std::error_code error;
  const fs::path result = fs::absolute(fs::path(value), error);
  if (error) return {};
  return result.lexically_normal();
}

bool Exists(const fs::path& path) {
  std::error_code error;
  return fs::exists(path, error);
}

bool IsDirectory(const fs::path& path) {
  std::error_code error;
  return fs::is_directory(path, error);
}

bool IsFile(const fs::path& path) {
  std::error_code error;
  return fs::is_regular_file(path, error);
}

bool SamePath(const fs::path& left, const fs::path& right) {
  return Lowercase(left.lexically_normal().wstring()) ==
         Lowercase(right.lexically_normal().wstring());
}

bool MoveWithRetry(const fs::path& source, const fs::path& destination,
                   std::wstring* error_message) {
  DWORD last_error = ERROR_SUCCESS;
  for (int attempt = 0; attempt < 40; ++attempt) {
    if (MoveFileExW(source.c_str(), destination.c_str(),
                    MOVEFILE_WRITE_THROUGH)) {
      return true;
    }
    last_error = GetLastError();
    if (last_error != ERROR_ACCESS_DENIED &&
        last_error != ERROR_SHARING_VIOLATION &&
        last_error != ERROR_LOCK_VIOLATION) {
      break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }
  if (error_message != nullptr) {
    *error_message = Win32Error(last_error);
  }
  return false;
}

bool RemoveTree(const fs::path& target, std::wstring* error_message) {
  std::error_code error;
  fs::remove_all(target, error);
  if (!error) return true;
  if (error_message != nullptr) {
    *error_message =
        L"Filesystem error " + std::to_wstring(error.value());
  }
  return false;
}

bool WaitForParent(DWORD parent_pid, std::wstring* error_message) {
  HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, parent_pid);
  if (parent == nullptr) {
    const DWORD error = GetLastError();
    if (error == ERROR_INVALID_PARAMETER) return true;
    if (error_message != nullptr) *error_message = Win32Error(error);
    return false;
  }

  const DWORD result = WaitForSingleObject(parent, INFINITE);
  CloseHandle(parent);
  if (result == WAIT_OBJECT_0) return true;
  if (error_message != nullptr) *error_message = Win32Error(GetLastError());
  return false;
}

bool ParseOptions(int argc, wchar_t* argv[], Options* options,
                  std::wstring* error_message) {
  for (int index = 1; index < argc; ++index) {
    const std::wstring argument(argv[index]);
    if (index + 1 >= argc) {
      *error_message = L"Missing value for " + argument;
      return false;
    }

    const std::wstring value(argv[++index]);
    if (argument == L"--install-root") {
      options->install_root = AbsolutePath(value);
    } else if (argument == L"--stage-root") {
      options->stage_root = AbsolutePath(value);
    } else if (argument == L"--startup-marker") {
      options->startup_marker = AbsolutePath(value);
    } else if (argument == L"--parent-pid") {
      wchar_t* end = nullptr;
      const unsigned long parsed = std::wcstoul(value.c_str(), &end, 10);
      if (end == value.c_str() || *end != L'\0' || parsed == 0 ||
          parsed > MAXDWORD) {
        *error_message = L"Invalid parent process id.";
        return false;
      }
      options->parent_pid = static_cast<DWORD>(parsed);
    } else {
      *error_message = L"Unknown argument: " + argument;
      return false;
    }
  }

  if (options->install_root.empty() || options->stage_root.empty() ||
      options->startup_marker.empty() || options->parent_pid == 0) {
    *error_message = L"Required updater arguments are missing.";
    return false;
  }
  return true;
}

bool ValidateOptions(const Options& options, std::wstring* error_message) {
  if (!IsDirectory(options.install_root) ||
      !IsDirectory(options.stage_root)) {
    *error_message = L"The install or staging directory does not exist.";
    return false;
  }
  if (options.install_root.filename().empty() ||
      SamePath(options.install_root, options.install_root.root_path())) {
    *error_message = L"The install directory is not a valid portable folder.";
    return false;
  }
  if (!SamePath(options.install_root.parent_path(),
                options.stage_root.parent_path()) ||
      options.stage_root.filename().wstring().rfind(L".avaca-update-", 0) !=
          0) {
    *error_message =
        L"The staging directory must be a sibling .avaca-update-* folder.";
    return false;
  }
  if (!IsFile(options.install_root / L"avaca.exe") ||
      !IsFile(options.stage_root / L"avaca.exe") ||
      !IsFile(options.stage_root / L"avaca_update.exe")) {
    *error_message = L"The install or staging directory is incomplete.";
    return false;
  }
  if (!SamePath(options.startup_marker.parent_path(), options.install_root)) {
    *error_message = L"The startup marker is outside the install directory.";
    return false;
  }
  return true;
}

bool LaunchAndWaitForStartup(const fs::path& install_root,
                             const fs::path& startup_marker,
                             std::wstring* error_message) {
  const fs::path executable = install_root / L"avaca.exe";
  std::wstring command_line = L"\"" + executable.wstring() + L"\"";
  std::vector<wchar_t> mutable_command(command_line.begin(),
                                        command_line.end());
  mutable_command.push_back(L'\0');

  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  if (!CreateProcessW(executable.c_str(), mutable_command.data(), nullptr,
                      nullptr, FALSE, 0, nullptr, install_root.c_str(),
                      &startup, &process)) {
    *error_message = L"Unable to start the updated AVACA: " +
                     Win32Error(GetLastError());
    return false;
  }

  bool started = false;
  for (int attempt = 0; attempt < 60; ++attempt) {
    if (GetFileAttributesW(startup_marker.c_str()) != INVALID_FILE_ATTRIBUTES) {
      started = true;
      break;
    }
    if (WaitForSingleObject(process.hProcess, 500) == WAIT_OBJECT_0) break;
  }

  if (!started) {
    TerminateProcess(process.hProcess, 1);
    *error_message =
        L"The updated AVACA did not report a successful startup.";
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return started;
}

void ScheduleSelfDelete() {
  wchar_t module_path[MAX_PATH] = {};
  const DWORD length = GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return;
  MoveFileExW(module_path, nullptr, MOVEFILE_DELAY_UNTIL_REBOOT);
}

int Run(const Options& options) {
  std::wstring error;
  if (!ValidateOptions(options, &error)) return Fail(error);
  if (!WaitForParent(options.parent_pid, &error)) {
    return Fail(L"Unable to wait for AVACA to exit: " + error);
  }

  DeleteFileW(options.startup_marker.c_str());
  const std::wstring suffix =
      L"-" + std::to_wstring(GetCurrentProcessId());
  const fs::path backup_root =
      options.install_root.parent_path() /
      (options.install_root.filename().wstring() + L".backup" + suffix);
  const fs::path failed_root =
      options.install_root.parent_path() /
      (options.install_root.filename().wstring() + L".failed" + suffix);

  if (Exists(backup_root) || Exists(failed_root)) {
    return Fail(L"A previous AVACA update backup already exists.");
  }

  bool backup_created = false;
  bool replacement_started = false;
  if (!MoveWithRetry(options.install_root, backup_root, &error)) {
    return Fail(L"Unable to move the current AVACA folder: " + error);
  }
  backup_created = true;

  if (!MoveWithRetry(options.stage_root, options.install_root, &error)) {
    Log(L"Unable to activate the staged AVACA folder: " + error);
    MoveWithRetry(backup_root, options.install_root, nullptr);
    return 1;
  }
  replacement_started = true;

  if (!LaunchAndWaitForStartup(options.install_root, options.startup_marker,
                               &error)) {
    Log(error);
    if (replacement_started) {
      RemoveTree(failed_root, nullptr);
      MoveWithRetry(options.install_root, failed_root, nullptr);
    }
    if (backup_created &&
        !MoveWithRetry(backup_root, options.install_root, &error)) {
      return Fail(L"Update failed and rollback was not possible: " + error);
    }
    RemoveTree(failed_root, nullptr);
    return 1;
  }

  DeleteFileW(options.startup_marker.c_str());
  if (!RemoveTree(backup_root, &error)) {
    Log(L"Updated successfully, but the backup could not be removed: " +
        error);
  }
  Log(L"AVACA portable update completed successfully.");
  ScheduleSelfDelete();
  return 0;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == nullptr) return Fail(L"Unable to read updater arguments.");

  Options options;
  std::wstring error;
  const int result = ParseOptions(argc, argv, &options, &error)
                         ? Run(options)
                         : Fail(error);
  LocalFree(argv);
  return result;
}

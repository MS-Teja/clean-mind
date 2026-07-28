#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>
#include <vector>

namespace {

// Ceiling for a Windows path once the process is long-path aware, which
// runner.exe.manifest declares us to be.
constexpr size_t kMaxWindowsPath = 32768;

void LogPathFailure(const wchar_t* step) {
  std::wstring message = L"[clean-mind] ";
  message += step;
  message += L" failed (GetLastError=";
  message += std::to_wstring(::GetLastError());
  message += L"), falling back to a relative asset path.\n";
  ::OutputDebugStringW(message.c_str());
}

// Full path of the running executable, with any symlink or other reparse
// point used to launch it resolved to its target. Empty on failure.
std::wstring GetResolvedExecutablePath() {
  std::vector<wchar_t> module_path(MAX_PATH);
  DWORD module_path_length = 0;
  while (true) {
    module_path_length = ::GetModuleFileNameW(
        nullptr, module_path.data(), static_cast<DWORD>(module_path.size()));
    if (module_path_length == 0) {
      LogPathFailure(L"GetModuleFileNameW");
      return std::wstring();
    }
    // On truncation the return value equals the buffer size.
    if (module_path_length < module_path.size()) {
      break;
    }
    if (module_path.size() >= kMaxWindowsPath) {
      LogPathFailure(L"GetModuleFileNameW (path too long)");
      return std::wstring();
    }
    module_path.resize(module_path.size() * 2);
  }

  // Requesting zero access rights asks only for metadata, so this succeeds
  // even though the loader holds the image open for execution. Omitting
  // FILE_FLAG_OPEN_REPARSE_POINT is what makes the handle refer to the
  // symlink's target rather than the symlink itself.
  HANDLE handle = ::CreateFileW(
      module_path.data(), 0,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    LogPathFailure(L"CreateFileW");
    return std::wstring();
  }

  const DWORD flags = FILE_NAME_NORMALIZED | VOLUME_NAME_DOS;
  std::wstring resolved(module_path_length + 1, L'\0');
  while (true) {
    DWORD resolved_length = ::GetFinalPathNameByHandleW(
        handle, resolved.data(), static_cast<DWORD>(resolved.size()), flags);
    if (resolved_length == 0) {
      LogPathFailure(L"GetFinalPathNameByHandleW");
      ::CloseHandle(handle);
      return std::wstring();
    }
    // Success returns the length excluding the null terminator; too small a
    // buffer returns the required size including it.
    if (resolved_length < resolved.size()) {
      resolved.resize(resolved_length);
      break;
    }
    if (resolved_length > kMaxWindowsPath) {
      LogPathFailure(L"GetFinalPathNameByHandleW (path too long)");
      ::CloseHandle(handle);
      return std::wstring();
    }
    resolved.resize(resolved_length);
  }
  ::CloseHandle(handle);

  if (resolved.rfind(L"\\\\?\\UNC\\", 0) == 0) {
    // \\?\UNC\server\share -> \\server\share
    resolved.replace(0, 8, L"\\\\");
  } else if (resolved.rfind(L"\\\\?\\", 0) == 0 && resolved.size() > 5 &&
             resolved[5] == L':') {
    // \\?\C:\... -> C:\..., matching the plain shape the engine already sees
    // from GetModuleFileName. Only drive-letter paths are safe to strip: a
    // volume GUID path (\\?\Volume{...}\) stops being absolute without it.
    resolved.erase(0, 4);
  }

  return resolved;
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::wstring GetDataDirectoryPath() {
  // Falling back to the relative path Flutter uses by default is always safe:
  // it is exactly the behaviour of a direct launch, which is the only case
  // that worked before this function existed.
  const std::wstring fallback = L"data";

  std::wstring executable_path = GetResolvedExecutablePath();
  if (executable_path.empty()) {
    return fallback;
  }

  size_t separator = executable_path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    LogPathFailure(L"locating the executable's directory");
    return fallback;
  }
  return executable_path.substr(0, separator + 1) + L"data";
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

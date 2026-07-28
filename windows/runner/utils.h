#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Returns the absolute path to the "data" directory next to the actual
// executable file on disk, resolving through any symlink/reparse point used
// to launch the process. Package managers that install via a symlink (e.g.
// winget's portable-app "Links" shims) make GetModuleFileName report the
// symlink's own location instead of the real install directory, which
// breaks Flutter's default relative-to-executable asset lookup.
std::wstring GetDataDirectoryPath();

#endif  // RUNNER_UTILS_H_

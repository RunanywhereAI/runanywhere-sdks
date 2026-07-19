#include "config/cli_paths.h"

#include <cstdlib>
#include <string>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <cstring>

#include <windows.h>
#endif

#include "rac/desktop/rac_desktop.h"

namespace rcli::paths {

namespace {

// Read an environment variable as UTF-8. On Windows std::getenv decodes the
// value through the process ANSI code page, corrupting Unicode paths (e.g. an
// international LOCALAPPDATA/USERPROFILE/RUNANYWHERE_HOME); read the wide value
// and convert with CP_UTF8 instead. Returns empty when unset or empty.
std::string getenv_utf8(const char* name) {
#if defined(_WIN32)
    const std::wstring wname(name, name + std::strlen(name));  // name is ASCII
    const wchar_t* wvalue = _wgetenv(wname.c_str());
    if (!wvalue || wvalue[0] == L'\0') {
        return {};
    }
    const int len = WideCharToMultiByte(CP_UTF8, 0, wvalue, -1, nullptr, 0, nullptr, nullptr);
    if (len <= 1) {
        return {};
    }
    std::string out(static_cast<size_t>(len - 1), '\0');  // len counts the NUL
    WideCharToMultiByte(CP_UTF8, 0, wvalue, -1, out.data(), len, nullptr, nullptr);
    return out;
#else
    const char* value = std::getenv(name);
    return (value && value[0] != '\0') ? std::string(value) : std::string();
#endif
}

}  // namespace

std::string normalize_dir(std::string dir) {
    while (dir.size() > 1 && (dir.back() == '/' || dir.back() == '\\')) {
        dir.pop_back();
    }
    return dir;
}

std::string resolve_home(const std::string& override_dir) {
    if (!override_dir.empty()) {
        return normalize_dir(override_dir);
    }
    if (std::string env = getenv_utf8("RUNANYWHERE_HOME"); !env.empty()) {
        return normalize_dir(std::move(env));
    }
    char buffer[1024] = {};
    if (rac_desktop_default_base_dir(buffer, sizeof(buffer)) == RAC_SUCCESS) {
        return buffer;
    }
    return {};
}

std::string state_dir() {
    if (std::string env = getenv_utf8("XDG_STATE_HOME"); !env.empty()) {
        return normalize_dir(std::move(env)) + "/runanywhere";
    }
    if (std::string home = getenv_utf8("HOME"); !home.empty()) {
        return normalize_dir(std::move(home)) + "/.local/state/runanywhere";
    }
#if defined(_WIN32)
    if (std::string local = getenv_utf8("LOCALAPPDATA"); !local.empty()) {
        return normalize_dir(std::move(local)) + "/RunAnywhere/state";
    }
    if (std::string profile = getenv_utf8("USERPROFILE"); !profile.empty()) {
        return normalize_dir(std::move(profile)) + "/AppData/Local/RunAnywhere/state";
    }
#endif
    return {};
}

}  // namespace rcli::paths

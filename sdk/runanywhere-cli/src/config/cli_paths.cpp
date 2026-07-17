#include "config/cli_paths.h"

#include <cstdlib>

#include "rac/desktop/rac_desktop.h"

namespace rcli::paths {

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
    if (const char* env = std::getenv("RUNANYWHERE_HOME"); env && env[0] != '\0') {
        return normalize_dir(env);
    }
    char buffer[1024] = {};
    if (rac_desktop_default_base_dir(buffer, sizeof(buffer)) == RAC_SUCCESS) {
        return buffer;
    }
    return {};
}

std::string state_dir() {
    if (const char* env = std::getenv("XDG_STATE_HOME"); env && env[0] != '\0') {
        return normalize_dir(env) + "/runanywhere";
    }
    if (const char* home = std::getenv("HOME"); home && home[0] != '\0') {
        return normalize_dir(home) + "/.local/state/runanywhere";
    }
#if defined(_WIN32)
    if (const char* local = std::getenv("LOCALAPPDATA"); local && local[0] != '\0') {
        return normalize_dir(local) + "/RunAnywhere/state";
    }
    if (const char* profile = std::getenv("USERPROFILE"); profile && profile[0] != '\0') {
        return normalize_dir(profile) + "/AppData/Local/RunAnywhere/state";
    }
#endif
    return {};
}

}  // namespace rcli::paths

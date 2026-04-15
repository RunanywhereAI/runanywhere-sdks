/**
 * @file src/internal/rac_platform_compat.h
 * @brief RunAnywhere Commons - Internal Platform Compatibility Layer
 *
 * Provides POSIX-like APIs on Windows (MSVC) so that the rest of the codebase
 * can use dirent.h, S_ISDIR, S_ISREG, etc. without #ifdef clutter.
 *
 * On non-Windows platforms this header is a no-op passthrough.
 *
 * INTERNAL ONLY. Not installed. Not visible to SDK consumers.
 *
 * Header history:
 *   This file used to live under `include/rac/core/rac_platform_compat.h`
 *   which leaked un-prefixed global names - `DIR`, `dirent`, `opendir`,
 *   `readdir`, `closedir`, `strcasecmp`, `strncasecmp`, `S_IS*`, `S_IFLNK` -
 *   into the public namespace on Windows. That violated the project's
 *   "all public symbols must be `rac_` prefixed" rule (PR #383 review
 *   comment). Moved to `src/internal/` so consumers never see it.
 *
 * Callers use `#include "internal/rac_platform_compat.h"` because the
 * PRIVATE include root is the src/ dir (configured in top-level
 * CMakeLists.txt via target_include_directories(rac_commons PRIVATE ...)).
 */

#ifndef RAC_PLATFORM_COMPAT_H
#define RAC_PLATFORM_COMPAT_H

#ifdef _WIN32

/* ---- POSIX string functions --------------------------------------------- */
#include <string.h>
#ifndef strcasecmp
#define strcasecmp _stricmp
#endif
#ifndef strncasecmp
#define strncasecmp _strnicmp
#endif

/* ---- stat / S_IS* macros ------------------------------------------------ */
#include <sys/stat.h>
#include <sys/types.h>

#ifndef S_ISDIR
#define S_ISDIR(m) (((m) & _S_IFMT) == _S_IFDIR)
#endif

#ifndef S_ISREG
#define S_ISREG(m) (((m) & _S_IFMT) == _S_IFREG)
#endif

#ifndef S_IFLNK
#define S_IFLNK 0120000
#endif

#ifndef S_ISLNK
#define S_ISLNK(m) (0) /* Windows does not have symlinks in the POSIX sense */
#endif

/* ---- dirent.h (minimal implementation) ---------------------------------- */
/* Provides opendir / readdir / closedir using Win32 FindFirstFile API.       */

#include <io.h>
#include <windows.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#ifndef NAME_MAX
#define NAME_MAX 260
#endif

struct dirent {
    char d_name[NAME_MAX + 1];
};

typedef struct DIR {
    HANDLE           hFind;
    WIN32_FIND_DATAA fdata;
    struct dirent    entry;
    int              first;   /* 1 = first call to readdir */
} DIR;

static inline DIR* opendir(const char* path) {
    if (!path || !*path) { errno = ENOENT; return NULL; }

    size_t len = strlen(path);
    /* Build search pattern: path\* */
    char* pattern = (char*)malloc(len + 3);
    if (!pattern) { errno = ENOMEM; return NULL; }
    memcpy(pattern, path, len);
    if (path[len - 1] != '\\' && path[len - 1] != '/') {
        pattern[len++] = '\\';
    }
    pattern[len++] = '*';
    pattern[len] = '\0';

    DIR* dir = (DIR*)malloc(sizeof(DIR));
    if (!dir) { free(pattern); errno = ENOMEM; return NULL; }

    dir->hFind = FindFirstFileA(pattern, &dir->fdata);
    free(pattern);

    if (dir->hFind == INVALID_HANDLE_VALUE) {
        free(dir);
        errno = ENOENT;
        return NULL;
    }
    dir->first = 1;
    return dir;
}

static inline struct dirent* readdir(DIR* dir) {
    if (!dir) return NULL;

    if (dir->first) {
        dir->first = 0;
    } else {
        if (!FindNextFileA(dir->hFind, &dir->fdata)) return NULL;
    }
    strncpy(dir->entry.d_name, dir->fdata.cFileName, NAME_MAX);
    dir->entry.d_name[NAME_MAX] = '\0';
    return &dir->entry;
}

static inline int closedir(DIR* dir) {
    if (!dir) return -1;
    FindClose(dir->hFind);
    free(dir);
    return 0;
}

#else /* !_WIN32 */

#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>

#endif /* _WIN32 */

/* ---- C++ helpers (available on all platforms) ---------------------------- */
#ifdef __cplusplus
#include <string>

#ifdef _WIN32
/**
 * Convert a UTF-8 std::string to std::wstring (UTF-16) for Windows wide-char APIs.
 * Uses MultiByteToWideChar so non-ASCII paths (Chinese, Japanese, accented chars)
 * convert correctly — a plain byte-widening copy would corrupt multi-byte UTF-8
 * sequences. Used by ONNX Runtime session creation which requires wchar_t*.
 */
inline std::wstring rac_to_wstring(const std::string& s) {
    if (s.empty()) return {};
    int size = MultiByteToWideChar(CP_UTF8, 0, s.data(),
                                   static_cast<int>(s.size()), nullptr, 0);
    if (size <= 0) return {};
    std::wstring out(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                        &out[0], size);
    return out;
}
inline std::wstring rac_to_wstring(const char* s) {
    if (!s || !*s) return {};
    return rac_to_wstring(std::string(s));
}
#endif
// ONNX Runtime path handling:
//   - On Windows, use `std::wstring wp = rac_to_wstring(p); session(env, wp.c_str(), opts);`
//   - On non-Windows, pass the `const char*` path directly.
// No macro is provided on purpose: a macro returning `rac_to_wstring(p).c_str()`
// would dangle at the end of the full-expression (the temporary wstring is
// destroyed before Ort::Session reads from the pointer).

#endif /* __cplusplus */

#endif /* RAC_PLATFORM_COMPAT_H */

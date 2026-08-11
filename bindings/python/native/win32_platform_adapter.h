// win32_platform_adapter.h — Windows implementation of rac_platform_adapter_t.
//
// Fills the mandatory rac_platform_adapter_t slots (file I/O, secure store, log,
// clock) plus the optional memory-info + directory-enumeration slots using
// std::filesystem + Win32 (GlobalMemoryStatusEx). HTTP download / archive
// extraction / vendor-id are left NULL (downloads are handled in pure Python).
// Ported verbatim from the runanywhere-electron M0 desktop adapter; only the
// fill symbol name and the DPAPI description string differ.
#ifndef RAC_PYTHON_WIN32_PLATFORM_ADAPTER_H
#define RAC_PYTHON_WIN32_PLATFORM_ADAPTER_H

#include "rac/core/rac_platform_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

// Populate *out with the Win32 adapter. `secure_dir` is the directory used for
// the DPAPI-encrypted secure store; it is created lazily on first secure_set.
// The struct is caller-owned and must outlive rac_shutdown().
void rac_python_fill_win32_adapter(rac_platform_adapter_t* out, const char* secure_dir);

#ifdef __cplusplus
}
#endif

#endif  // RAC_PYTHON_WIN32_PLATFORM_ADAPTER_H

// win32_platform_adapter.h — Windows implementation of rac_platform_adapter_t.
//
// Fills the mandatory rac_platform_adapter_t slots (file I/O, secure store, log,
// clock) plus the optional memory-info + directory-enumeration slots using
// std::filesystem + Win32 (GlobalMemoryStatusEx). HTTP download / archive
// extraction / vendor-id are left NULL. This is the M0 desktop adapter the
// runanywhere-electron N-API addon builds on; the production addon will upgrade
// the secure store to DPAPI and add a WinHTTP/undici HTTP transport.
#ifndef RAC_ELECTRON_WIN32_PLATFORM_ADAPTER_H
#define RAC_ELECTRON_WIN32_PLATFORM_ADAPTER_H

#include "rac/core/rac_platform_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

// Populate *out with the Win32 adapter. `secure_dir` is the directory used for
// the (M0, plaintext) secure store; it is created lazily on first secure_set.
// The struct is caller-owned and must outlive rac_shutdown().
void rac_electron_fill_win32_adapter(rac_platform_adapter_t* out, const char* secure_dir);

#ifdef __cplusplus
}
#endif

#endif  // RAC_ELECTRON_WIN32_PLATFORM_ADAPTER_H

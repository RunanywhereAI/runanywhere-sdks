// posix_platform_adapter.h — cross-platform POSIX implementation of
// rac_platform_adapter_t (Linux + macOS).
//
// Mirrors win32_platform_adapter.h slot-for-slot: fills the mandatory
// rac_platform_adapter_t slots (file I/O, secure store, log, clock) plus the
// optional memory-info + directory-enumeration slots using std::filesystem +
// POSIX APIs (sysconf on Linux, sysctl/host_statistics64 on macOS). HTTP
// download / archive extraction / vendor-id are left NULL (downloads are handled
// in pure Python). The secure store is a plaintext file store restricted to the
// owner (0600 files inside a 0700 directory); a real macOS Keychain backend is a
// later upgrade (see the seam comment in the .cpp).
#ifndef RAC_PYTHON_POSIX_PLATFORM_ADAPTER_H
#define RAC_PYTHON_POSIX_PLATFORM_ADAPTER_H

#include "rac/core/rac_platform_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

// Populate *out with the POSIX adapter. `secure_dir` is the directory used for
// the owner-only secure store; it is created lazily (mode 0700) on first
// secure_set. The struct is caller-owned and must outlive rac_shutdown().
void rac_python_fill_posix_adapter(rac_platform_adapter_t* out, const char* secure_dir);

#ifdef __cplusplus
}
#endif

#endif  // RAC_PYTHON_POSIX_PLATFORM_ADAPTER_H

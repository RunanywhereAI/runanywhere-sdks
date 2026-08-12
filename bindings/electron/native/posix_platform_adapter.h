// posix_platform_adapter.h — cross-platform POSIX implementation of
// rac_platform_adapter_t (Linux + macOS).
//
// Mirrors win32_platform_adapter.h slot-for-slot: fills the mandatory
// rac_platform_adapter_t slots (file I/O, secure store, log, clock) plus the
// optional memory-info + directory-enumeration slots using std::filesystem +
// POSIX APIs (sysconf on Linux, sysctl/host_statistics64 on macOS).
//
// http_download / http_download_cancel stay NULL on purpose. Desktop downloads
// use the process-wide HTTP *transport* vtable registered in addon init
// (`rac_desktop_http_transport_register` when RAC_DESKTOP_ADAPTER=ON / libcurl) —
// not the async adapter download slot (that slot is for Web/Emscripten). Do not
// fill http_download here. extract_archive / get_vendor_id also stay NULL
// (commons extracts via rac_extract_archive_native; vendor-id is Apple-only).
//
// The secure store is a plaintext file store restricted to the owner (0600
// files inside a 0700 directory); a real macOS Keychain / Linux Secret Service
// backend is a later upgrade (see the seam comment in the .cpp).
#ifndef RAC_ELECTRON_POSIX_PLATFORM_ADAPTER_H
#define RAC_ELECTRON_POSIX_PLATFORM_ADAPTER_H

#include "rac/core/rac_platform_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

// Populate *out with the POSIX adapter. `secure_dir` is the directory used for
// the owner-only secure store; it is created lazily (mode 0700) on first
// secure_set. The struct is caller-owned and must outlive rac_shutdown().
void rac_electron_fill_posix_adapter(rac_platform_adapter_t* out, const char* secure_dir);

#ifdef __cplusplus
}
#endif

#endif  // RAC_ELECTRON_POSIX_PLATFORM_ADAPTER_H

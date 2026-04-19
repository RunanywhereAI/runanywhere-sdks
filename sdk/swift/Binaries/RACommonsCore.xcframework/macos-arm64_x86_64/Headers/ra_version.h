// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — C ABI version constants.
//
// The C ABI version is a single uint32 compared exactly. Frontends built
// against a given ABI version must NOT load a plugin built against a
// different ABI version. Every engine plugin exports `ra_plugin_abi_version()`
// which is checked at load time.

#ifndef RA_VERSION_H
#define RA_VERSION_H

#ifdef __cplusplus
extern "C" {
#endif

// Bump this whenever the C ABI layout changes. MAJOR.MINOR.PATCH encoded as
// (MAJOR << 16) | (MINOR << 8) | PATCH.
#define RA_ABI_VERSION_MAJOR 2
#define RA_ABI_VERSION_MINOR 0
#define RA_ABI_VERSION_PATCH 0

#define RA_ABI_VERSION ((RA_ABI_VERSION_MAJOR << 16) | \
                        (RA_ABI_VERSION_MINOR << 8)  | \
                         RA_ABI_VERSION_PATCH)

// Returns the ABI version of the core shipped in the binary that exports this
// symbol. Callers must compare against RA_ABI_VERSION and reject on mismatch.
unsigned int ra_abi_version(void);

// Returns the plugin API version. Same format as ra_abi_version; bumped
// independently — the plugin API is narrower than the full C ABI and changes
// less often.
#define RA_PLUGIN_API_VERSION_MAJOR 1
#define RA_PLUGIN_API_VERSION_MINOR 0
#define RA_PLUGIN_API_VERSION_PATCH 0

#define RA_PLUGIN_API_VERSION                          \
    ((RA_PLUGIN_API_VERSION_MAJOR << 16) |             \
     (RA_PLUGIN_API_VERSION_MINOR << 8)  |             \
      RA_PLUGIN_API_VERSION_PATCH)

unsigned int ra_plugin_api_version(void);

// Returns a human-readable build string ("2.0.0+git.a1b2c3d") set at link
// time. Safe to read from any thread; the returned pointer is static.
const char* ra_build_info(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_VERSION_H

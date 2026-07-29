// win_msvc_compat.h — MSVC forced-include (/FI) compatibility shim (Windows only).
//
// <winnt.h> (pulled by <windows.h>) defines ERROR_SEVERITY_SUCCESS /
// ERROR_SEVERITY_INFORMATIONAL / ERROR_SEVERITY_WARNING / ERROR_SEVERITY_ERROR,
// and <wingdi.h> defines ERROR, as preprocessor macros. These collide with the
// generated protobuf enum values in the RunAnywhere IDL — e.g.
// `runanywhere::ErrorSeverity::ERROR_SEVERITY_WARNING` in
// src/generated/proto/errors.pb.h, which otherwise expands to `0x80000000 = 3`
// and fails to compile.
//
// Renaming the enum values would drift the error surface across all five SDKs
// (forbidden — see idl/errors.proto). Instead we pull <windows.h> ONCE here (so
// its include guard is set) and #undef the offending macros; any later
// <windows.h> include in the translation unit is then a no-op, so the macros
// stay gone and the generated headers parse cleanly. No proto or source drift.
//
// Wired in via `/FI` on the rac_commons target for MSVC only
// (sdk/runanywhere-commons/CMakeLists.txt).

#ifndef RAC_WIN_MSVC_COMPAT_H
#define RAC_WIN_MSVC_COMPAT_H

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

// winnt.h severity macros (collide with the ErrorSeverity proto enum).
#undef ERROR_SEVERITY_SUCCESS
#undef ERROR_SEVERITY_INFORMATIONAL
#undef ERROR_SEVERITY_WARNING
#undef ERROR_SEVERITY_ERROR

// Other common Win32 macros that collide with generated enum identifiers.
#undef ERROR
#undef DELETE
#undef OPTIONAL

#endif  // _WIN32

#endif  // RAC_WIN_MSVC_COMPAT_H

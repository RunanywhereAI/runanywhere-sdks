#ifndef RCLI_WINDOWS_PROTO_COMPAT_H
#define RCLI_WINDOWS_PROTO_COMPAT_H

// Force-included ahead of every rcli translation unit on Windows (see the CLI
// CMakeLists). <winnt.h> — pulled in via <windows.h> by Abseil/protobuf headers
// the CLI transitively includes — defines ERROR_SEVERITY_WARNING and
// ERROR_SEVERITY_ERROR as preprocessor macros. Those clobber the identically
// named values of the generated proto enum runanywhere::v1::ErrorSeverity,
// breaking errors.pb.h with "expected '}' before numeric constant" wherever a
// TU includes windows.h before the proto header (e.g. cmd_run.cpp).
//
// Include windows.h once up front and undef only the two colliding macros, so
// later proto headers parse cleanly. Subsequent <windows.h> includes are no-ops
// (its own include guard), so the undefs stick.

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#undef ERROR_SEVERITY_WARNING
#undef ERROR_SEVERITY_ERROR
#endif  // _WIN32

#endif  // RCLI_WINDOWS_PROTO_COMPAT_H

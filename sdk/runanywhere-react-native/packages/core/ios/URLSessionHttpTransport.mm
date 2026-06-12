// SPDX-License-Identifier: Apache-2.0
//
// URLSessionHttpTransport.mm (React Native wrapper)
//
// Per-SDK wrapper around the canonical implementation in
//   sdk/shared/ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm
//
// flutter-core-012: this used to be a 462-line standalone copy of the
// implementation that drifted from the Flutter version (no host-session
// override, no `X-RAC-Range-Honored`, no `os_log`, no per-stream registry
// for `cancelAllStreams`). It has been collapsed into a thin shim that
// defines the RN-specific C entry-point and ObjC class prefixes and
// `#include`s the canonical body, so the Flutter and React Native plugins
// share one source of truth. The exported symbols
//   - rn_register_urlsession_transport
//   - rn_unregister_urlsession_transport
//   - rn_set_streaming_session
//   - rn_cancel_all_streams
// are all wired into the RN Swift façade at `URLSessionHttpTransport.swift`
// (matching the Flutter and Swift SDK source of truth) and consumed by
// `HybridRunAnywhereCore.cpp` during SDK bootstrap.
//
// The canonical implementation is co-located at
// ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm when built
// from a published npm package (staged by the prepack script). When built
// inside the monorepo without a prior prepack, the path resolves via the
// repo-relative fallback below. Both paths are probed at compile time using
// __has_include so no HEADER_SEARCH_PATHS entry is needed in either context.

#define RAC_URLS_C_PREFIX    rn
#define RAC_URLS_OBJC_PREFIX RNRunAnywhere

#if __has_include("URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm")
#include "URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm"
#else
#include "../../../../shared/ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm"
#endif

#undef RAC_URLS_C_PREFIX
#undef RAC_URLS_OBJC_PREFIX

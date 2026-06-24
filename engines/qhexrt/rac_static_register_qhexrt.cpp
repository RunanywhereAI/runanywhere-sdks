/**
 * @file rac_static_register_qhexrt.cpp
 * @brief Static registration shim for the QHexRT engine plugin.
 *
 * Used only in static-plugin builds (RAC_STATIC_PLUGINS / RAC_PLUGIN_MODE_STATIC,
 * e.g. iOS / WASM). On the default Android / Linux SHARED path the host loads
 * the carrier `.so` and calls `rac_backend_qhexrt_register()` directly.
 *
 * Routes through `rac_backend_qhexrt_register()` (idempotent) so the static-init
 * path and the dynamic path register the plugin identically.
 */

#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_REGISTER_BACKEND(qhexrt);
#endif

/**
 * @file rac_static_register_qhexrt.cpp
 * @brief Static registration shim for the QHexRT engine plugin.
 *
 * Used only in static-plugin builds (RAC_STATIC_PLUGINS / RAC_PLUGIN_MODE_STATIC,
 * e.g. iOS / WASM). On the default Android / Linux SHARED path the host loads
 * the carrier `.so` and calls `rac_plugin_entry_qhexrt()` via dlsym instead.
 *
 * QHexRT needs no engine-specific bring-up (no CPU-runtime provider like
 * llamacpp), so the bare RAC_STATIC_PLUGIN_REGISTER is sufficient.
 */

#include "rac/plugin/rac_plugin_entry.h"

extern "C" RAC_PLUGIN_ENTRY_DECL(qhexrt);

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(qhexrt);
#endif

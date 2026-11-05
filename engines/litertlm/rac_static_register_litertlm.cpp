/**
 * @file rac_static_register_litertlm.cpp
 * @brief Static-init registration of the LiteRT-LM engine plugin.
 *
 * Compiled only when RAC_STATIC_PLUGINS=ON (iOS, WASM). Routes through the
 * idempotent rac_backend_litertlm_register() so the static and dynamic paths
 * register the plugin identically.
 */

#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_REGISTER_BACKEND(litertlm);
#endif

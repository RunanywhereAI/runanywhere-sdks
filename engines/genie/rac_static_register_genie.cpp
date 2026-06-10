/**
 * @file rac_static_register_genie.cpp
 * @brief Static registration shim for the Qualcomm Genie engine plugin.
 */

#include "rac/plugin/rac_plugin_entry.h"

extern "C" RAC_PLUGIN_ENTRY_DECL(genie);

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(genie);
#endif

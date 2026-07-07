/**
 * @file rac_static_register_mlx.cpp
 * @brief Static registration shim for the MLX engine plugin.
 */

#include "rac/backends/rac_mlx.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_mlx.h"

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_REGISTER_BACKEND(mlx);
#endif

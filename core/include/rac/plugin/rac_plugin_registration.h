/**
 * @file rac_plugin_registration.h
 * @brief Shared policy for host-facing backend registration results.
 */

#ifndef RAC_PLUGIN_REGISTRATION_H
#define RAC_PLUGIN_REGISTRATION_H

#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Return true when a registration attempt leaves a backend registered.
 * BUSY refuses replacement because the existing plugin serves a leased model;
 * DUPLICATE keeps the higher-priority plugin. Neither means the new plugin was
 * installed. Use only for registration/load results, never for unload or inference.
 * Header-only so SDK bridges need no additional exported commons symbol.
 */
static inline rac_bool_t rac_plugin_registration_succeeded(rac_result_t result) {
    return (result == RAC_SUCCESS || result == RAC_ERROR_PLUGIN_DUPLICATE ||
            result == RAC_ERROR_PLUGIN_BUSY || result == RAC_ERROR_MODULE_ALREADY_REGISTERED)
               ? RAC_TRUE
               : RAC_FALSE;
}

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_REGISTRATION_H */

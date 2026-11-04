/**
 * @file rac_plugin_registration.h
 * @brief Shared policy for host-facing backend registration results.
 */

#ifndef RAC_PLUGIN_REGISTRATION_H
#define RAC_PLUGIN_REGISTRATION_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

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

/* Requires LOG_CAT to be defined at the call site. */
#define RAC_PLUGIN_UNREGISTER_BUSY_CHECK(name, result)                                          \
    do {                                                                                        \
        if ((result) == RAC_ERROR_PLUGIN_BUSY) {                                                \
            return (result);                                                                    \
        }                                                                                       \
        if ((result) != RAC_SUCCESS && (result) != RAC_ERROR_NOT_FOUND &&                       \
            (result) != RAC_ERROR_MODULE_NOT_FOUND) {                                           \
            RAC_LOG_WARNING(LOG_CAT, "rac_plugin_unregister('" name "') failed: %d", (result)); \
        }                                                                                       \
    } while (0)

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_REGISTRATION_H */

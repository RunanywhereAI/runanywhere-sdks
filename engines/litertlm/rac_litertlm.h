/**
 * @file rac_litertlm.h
 * @brief Registration entry points of the LiteRT-LM engine plugin.
 */

#ifndef RUNANYWHERE_RAC_LITERTLM_H
#define RUNANYWHERE_RAC_LITERTLM_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

rac_result_t rac_backend_litertlm_register(void);
rac_result_t rac_backend_litertlm_unregister(void);
rac_bool_t rac_backend_litertlm_is_registered(void);

#ifdef __cplusplus
}
#endif

#endif  // RUNANYWHERE_RAC_LITERTLM_H

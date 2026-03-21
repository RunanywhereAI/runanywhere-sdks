/**
 * @file rac_backend_metalrt.h
 * @brief MetalRT backend registration API (copy for Swift module)
 *
 * This is a copy of include/rac/backends/rac_backend_metalrt.h
 * placed here so the Swift module can find it without the full include path.
 */

#ifndef RAC_BACKEND_METALRT_H
#define RAC_BACKEND_METALRT_H

#include "rac_types.h"
#include "rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) || defined(__clang__)
#define RAC_METALRT_API __attribute__((visibility("default")))
#else
#define RAC_METALRT_API
#endif

RAC_METALRT_API rac_result_t rac_backend_metalrt_register(void);
RAC_METALRT_API rac_result_t rac_backend_metalrt_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BACKEND_METALRT_H */

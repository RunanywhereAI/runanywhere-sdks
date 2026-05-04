/**
 * @file rac_platform_services.h
 * @brief RunAnywhere Commons - Platform service availability callbacks
 *
 * Platform SDKs can register a lightweight availability callback for services
 * that are supplied by the host OS rather than by a native ML backend.
 */

#ifndef RAC_PLATFORM_SERVICES_H
#define RAC_PLATFORM_SERVICES_H

#include <stdint.h>

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rac_platform_service {
    RAC_PLATFORM_SERVICE_FOUNDATION_MODELS = 1,
    RAC_PLATFORM_SERVICE_SYSTEM_TTS = 2,
    RAC_PLATFORM_SERVICE_SYSTEM_STT = 3,
} rac_platform_service_t;

typedef rac_bool_t (*rac_platform_service_availability_callback_t)(int32_t service,
                                                                   void* user_data);

RAC_API rac_result_t rac_platform_services_register_availability_callback(
    rac_platform_service_availability_callback_t callback);

RAC_API rac_bool_t rac_platform_services_is_available(rac_platform_service_t service);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLATFORM_SERVICES_H */

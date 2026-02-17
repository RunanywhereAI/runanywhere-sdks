/**
 * @file rac_diffusion_sdcpp.h
 * @brief RunAnywhere Commons - stable-diffusion.cpp Backend Registration
 *
 * Minimal header exposing only the backend registration function.
 * The full diffusion API (types, options, results) is available through
 * the CRACommons module. This header exists solely for the SdcppRuntime
 * Swift module to call rac_backend_sdcpp_register().
 */

#ifndef RAC_DIFFUSION_SDCPP_H
#define RAC_DIFFUSION_SDCPP_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register the sd.cpp diffusion backend with the service registry.
 *
 * After registration, the service registry will route diffusion requests
 * to this backend when the model is in sd.cpp-compatible format
 * (.safetensors, .gguf, .ckpt) or when framework is explicitly set to SDCPP.
 *
 * Registers with priority 90 (CoreML is 100, so CoreML is preferred
 * by default on Apple platforms).
 *
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_backend_sdcpp_register(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DIFFUSION_SDCPP_H */

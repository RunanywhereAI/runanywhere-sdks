/**
 * @file rac_llm_llamacpp.h
 * @brief Backend registration API for LlamaCPP
 *
 * Forward declarations for LlamaCPP backend registration functions.
 * These symbols are exported by RABackendLLAMACPP.xcframework.
 */

#ifndef RAC_LLM_LLAMACPP_H
#define RAC_LLM_LLAMACPP_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Register the LlamaCPP backend with the RACommons service registry.
 * @return RAC_SUCCESS on success, RAC_ERROR_MODULE_ALREADY_REGISTERED if already registered
 */
rac_result_t rac_backend_llamacpp_register(void);

/**
 * Unregister the LlamaCPP backend from the RACommons service registry.
 * @return RAC_SUCCESS on success
 */
rac_result_t rac_backend_llamacpp_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_LLAMACPP_H */

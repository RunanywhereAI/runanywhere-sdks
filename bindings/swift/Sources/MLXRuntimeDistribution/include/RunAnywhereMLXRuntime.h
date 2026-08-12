/**
 * @file RunAnywhereMLXRuntime.h
 * @brief Stable C lifecycle ABI for the packaged Apple MLX runtime.
 *
 * Inference remains implemented once in the canonical Swift MLXRuntime target.
 * Flutter and React Native use these symbols only to retain and register that
 * implementation against the process-wide Commons plugin registry.
 */

#ifndef RUNANYWHERE_MLX_RUNTIME_H
#define RUNANYWHERE_MLX_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t ra_mlx_register_runtime(int32_t priority);
int32_t ra_mlx_unregister_runtime(void);
int32_t ra_mlx_runtime_is_registered(void);
int32_t ra_mlx_runtime_is_available(void);

#ifdef __cplusplus
}
#endif

#endif /* RUNANYWHERE_MLX_RUNTIME_H */

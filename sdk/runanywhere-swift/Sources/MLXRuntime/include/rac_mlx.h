/**
 * @file rac_mlx.h
 * @brief Swift-facing MLX ABI shim.
 *
 * The callback ABI lives in commons. This forwarding header keeps SwiftPM's
 * flattened CRACommons include layout usable without duplicating the structs.
 */

#ifndef RUNANYWHERE_SWIFT_MLX_RUNTIME_RAC_MLX_FORWARDING_H
#define RUNANYWHERE_SWIFT_MLX_RUNTIME_RAC_MLX_FORWARDING_H

#include "rac/backends/rac_mlx.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ra_mlx_clear_cancel_fn)(rac_handle_t handle, void* user_data);

rac_result_t ra_mlx_set_clear_cancel_callback(ra_mlx_clear_cancel_fn callback, void* user_data);

#ifdef __cplusplus
}
#endif

#endif /* RUNANYWHERE_SWIFT_MLX_RUNTIME_RAC_MLX_FORWARDING_H */

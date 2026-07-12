/**
 * @file rac_mlx_callbacks_internal.h
 * @brief Snapshot helper for the MLX Swift callback table.
 */

#ifndef ENGINES_MLX_RAC_MLX_CALLBACKS_INTERNAL_H
#define ENGINES_MLX_RAC_MLX_CALLBACKS_INTERNAL_H

#include "rac/backends/rac_mlx.h"

extern "C" {

typedef void (*ra_mlx_clear_cancel_fn)(rac_handle_t handle, void* user_data);

rac_result_t ra_mlx_set_clear_cancel_callback(ra_mlx_clear_cancel_fn callback, void* user_data);
}

namespace runanywhere::commons::mlx {

bool snapshot_callbacks(rac_mlx_callbacks_t* out);
void clear_cancel(rac_handle_t handle);

}  // namespace runanywhere::commons::mlx

#endif  // ENGINES_MLX_RAC_MLX_CALLBACKS_INTERNAL_H

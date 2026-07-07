/**
 * @file rac_mlx_callbacks_internal.h
 * @brief Snapshot helper for the MLX Swift callback table.
 */

#ifndef ENGINES_MLX_RAC_MLX_CALLBACKS_INTERNAL_H
#define ENGINES_MLX_RAC_MLX_CALLBACKS_INTERNAL_H

#include "rac/backends/rac_mlx.h"

namespace runanywhere::commons::mlx {

bool snapshot_callbacks(rac_mlx_callbacks_t* out);

}  // namespace runanywhere::commons::mlx

#endif  // ENGINES_MLX_RAC_MLX_CALLBACKS_INTERNAL_H

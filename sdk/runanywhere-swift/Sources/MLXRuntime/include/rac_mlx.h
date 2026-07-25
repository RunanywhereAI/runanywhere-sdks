/**
 * @file rac_mlx.h
 * @brief Swift-facing MLX ABI shim.
 *
 * The callback ABI lives in commons. This forwarding header keeps SwiftPM's
 * flattened CRACommons include layout usable without duplicating the structs.
 */

#ifndef RUNANYWHERE_SWIFT_MLX_RUNTIME_RAC_MLX_FORWARDING_H
#define RUNANYWHERE_SWIFT_MLX_RUNTIME_RAC_MLX_FORWARDING_H

#if __has_include("../../../../runanywhere-commons/include/rac/backends/rac_mlx.h")
// In-repo builds must prefer the canonical source header. The local
// RACommons XCFramework can legitimately lag while a coordinated callback ABI
// change is being compiled and tested; selecting its packaged copy first
// would make Swift see the previous struct layout.
#include "../../../../runanywhere-commons/include/rac/backends/rac_mlx.h"
#elif __has_include("rac/backends/rac_mlx.h")
// Published/package-only builds do not carry the source tree. Resolve against
// the RACommons XCFramework header that the application links.
#include "rac/backends/rac_mlx.h"
#else
#error "RunAnywhere MLX callback ABI header not found"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ra_mlx_clear_cancel_fn)(rac_handle_t handle, void* user_data);

rac_result_t ra_mlx_set_clear_cancel_callback(ra_mlx_clear_cancel_fn callback, void* user_data);

#ifdef __cplusplus
}
#endif

#endif /* RUNANYWHERE_SWIFT_MLX_RUNTIME_RAC_MLX_FORWARDING_H */

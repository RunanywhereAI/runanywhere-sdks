#pragma once

#include <stddef.h>

#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

rac_result_t rac_metal_runtime_require_available(void);
rac_result_t rac_metal_runtime_alloc_host_buffer(size_t bytes, void** out_data);
void rac_metal_runtime_free_host_buffer(void* data);

#ifdef __cplusplus
}
#endif

#pragma once

#include <cstddef>

#include "rac/core/rac_error.h"

extern "C" {

rac_result_t rac_metal_runtime_require_available(void);
rac_result_t rac_metal_runtime_alloc_host_buffer(size_t bytes, void** out_data);
void rac_metal_runtime_free_host_buffer(void* data);

}

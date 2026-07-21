#pragma once

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

namespace rac::vocoder {

rac_result_t create_service(const char* model_id, const char* config_json,
                            rac_handle_t* out_handle);

}  // namespace rac::vocoder

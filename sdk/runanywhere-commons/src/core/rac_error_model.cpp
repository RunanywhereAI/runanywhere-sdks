#include "rac/core/rac_error_model.h"
#include "rac/core/rac_error.h"

#include <string.h>

// ------------------------------------------------------------
// Internal Helper: Determine Category from Error Code Range
// ------------------------------------------------------------
const char* rac_error_category(rac_result_t code) {
    if (code >= -109 && code <= -100) return "Initialization";
    if (code >= -129 && code <= -110) return "Model";
    if (code >= -149 && code <= -130) return "Generation";
    if (code >= -179 && code <= -150) return "Network";
    if (code >= -219 && code <= -180) return "Storage";
    if (code >= -229 && code <= -220) return "Hardware";
    if (code >= -249 && code <= -230) return "ComponentState";
    if (code >= -279 && code <= -250) return "Validation";
    if (code >= -299 && code <= -280) return "Audio";
    if (code >= -319 && code <= -300) return "LanguageVoice";
    if (code >= -329 && code <= -320) return "Authentication";
    if (code >= -349 && code <= -330) return "Security";
    if (code >= -369 && code <= -350) return "Extraction";
    if (code >= -379 && code <= -370) return "Calibration";
    if (code >= -499 && code <= -400) return "ModuleService";
    if (code >= -599 && code <= -500) return "PlatformAdapter";
    if (code >= -699 && code <= -600) return "Backend";
    if (code >= -799 && code <= -700) return "Event";
    if (code >= -899 && code <= -800) return "Other";

    if (code == RAC_SUCCESS) return "Success";

    return "Unknown";
}

// ------------------------------------------------------------
// Public API: Create Structured Error Model
// ------------------------------------------------------------
rac_error_model_t rac_make_error_model(rac_result_t code) {
    rac_error_model_t model;
    model.code = code;
    model.message = rac_error_message(code);
    model.category = rac_error_category(code);
    return model;
}
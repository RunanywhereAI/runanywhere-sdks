/**
 * @file genie_backend.cpp
 * @brief Qualcomm Genie engine shell implementation.
 *
 * GAP 06 T5.2. This shell compiles on every host regardless of SDK
 * availability. When `RAC_GENIE_SDK_AVAILABLE=0`, registration is rejected
 * before the router can select Genie; any direct stub invocation still returns
 * `RAC_ERROR_BACKEND_UNAVAILABLE`.
 */

#include "genie_backend.h"

#include "rac/core/rac_logger.h"

#if RAC_GENIE_SDK_AVAILABLE
// Phase 2 — real Qualcomm Genie integration. The headers listed below
// ship with QAIRT / QNN 2.24+ and are not vendored in this repo.
//   #include <GenieCommon.h>
//   #include <GenieDialog.h>
//   #include <GenieLog.h>
#endif

extern "C" {

const char* genie_backend_build_info(void) {
#if RAC_GENIE_SDK_AVAILABLE
    return "genie:sdk-available";
#else
    return "genie:sdk-unavailable";
#endif
}

rac_result_t genie_backend_unavailable(void) {
    RAC_LOG_WARNING("Genie",
                    "Genie backend unavailable. It requires an Android build "
                    "with -DRAC_BACKEND_GENIE=ON, "
                    "-DRAC_GENIE_SDK_ROOT=<qnn-sdk-path>, and SDK-backed LLM ops.");
    return RAC_ERROR_BACKEND_UNAVAILABLE;
}

}  // extern "C"

/**
 * @file genie_backend.cpp
 * @brief Qualcomm Genie engine shell implementation.
 *
 * This shell compiles on every host regardless of SDK
 * availability. Registration is rejected before the router can select Genie
 * (see `genie_capability_check()` in rac_plugin_entry_genie.cpp). This TU now
 * only carries the `genie_backend_build_info()` marker used by tests.
 */

#include "genie_backend.h"

#if RAC_GENIE_SDK_AVAILABLE
// Real Qualcomm Genie integration. The headers listed below
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

}  // extern "C"

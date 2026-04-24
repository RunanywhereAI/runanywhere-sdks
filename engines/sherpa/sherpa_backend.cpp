/**
 * @file sherpa_backend.cpp
 * @brief Shell implementation for the Sherpa-ONNX engine plugin.
 *
 * See sherpa_backend.h for the T5.1 phase split plan. Intentionally empty
 * at the source level — this file exists so the `rac_backend_sherpa`
 * CMake target has at least one implementation TU (required on Apple's
 * ld which refuses to build empty archives) and so the plugin entry
 * point in `rac_plugin_entry_sherpa.cpp` can reference translation-unit
 * globals from a file that compiles on every supported platform.
 */

#include "sherpa_backend.h"

namespace runanywhere {
namespace sherpa {

// Exported so the plugin library has at least one non-trivial symbol
// even when the shell has no logic. Lets linker verification pass
// without emitting an `empty library` diagnostic on Xcode generators.
extern "C" const char* rac_sherpa_build_tag() {
    return kSherpaOnnxAvailable ? "sherpa-onnx-available"
                                : "sherpa-onnx-unavailable";
}

}  // namespace sherpa
}  // namespace runanywhere

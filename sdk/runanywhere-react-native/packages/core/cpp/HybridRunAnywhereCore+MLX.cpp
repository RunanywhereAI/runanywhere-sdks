/**
 * React Native bridge for the Apple MLX Swift runtime.
 *
 * MLX execution is implemented in the Swift `RunAnywhereMLX` product. React
 * Native stays in charge of the public registration call, but native C++ only
 * discovers the Swift runtime through exported C symbols so Android/non-Apple
 * builds remain clean no-ops.
 */

#include "HybridRunAnywhereCore+Common.hpp"

#include "rac/core/rac_error.h"

#include <cstdint>
#include <string>

#if __has_include(<dlfcn.h>)
#include <dlfcn.h>
#endif

namespace margelo::nitro::runanywhere {
namespace {

using MLXRegisterRuntimeFn = int32_t (*)(int32_t);
using MLXNoArgIntFn = int32_t (*)();

template <typename Fn>
Fn lookupMLXRuntimeSymbol(const char *symbol) {
#if __has_include(<dlfcn.h>)
  return reinterpret_cast<Fn>(dlsym(RTLD_DEFAULT, symbol));
#else
  (void)symbol;
  return nullptr;
#endif
}

bool isRACSuccess(int32_t result) {
  return result == RAC_SUCCESS ||
         result == RAC_ERROR_MODULE_ALREADY_REGISTERED ||
         result == RAC_ERROR_PLUGIN_DUPLICATE;
}

bool callMLXNoArgBoolSymbol(const char *symbol) {
  auto fn = lookupMLXRuntimeSymbol<MLXNoArgIntFn>(symbol);
  return fn != nullptr && fn() != 0;
}

} // namespace

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::mlxRuntimeAvailable() {
  return Promise<bool>::async([]() {
    return callMLXNoArgBoolSymbol("ra_mlx_runtime_is_available");
  });
}

std::shared_ptr<Promise<bool>>
HybridRunAnywhereCore::mlxRegisterBackend(double priority) {
  return Promise<bool>::async([priority]() {
    auto fn =
        lookupMLXRuntimeSymbol<MLXRegisterRuntimeFn>("ra_mlx_register_runtime");
    if (fn == nullptr) {
      return false;
    }

    const auto clampedPriority =
        priority < 0 ? 0 : (priority > 2147483647.0 ? 2147483647.0 : priority);
    return isRACSuccess(fn(static_cast<int32_t>(clampedPriority)));
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::mlxUnregisterBackend() {
  return Promise<bool>::async([]() {
    auto fn =
        lookupMLXRuntimeSymbol<MLXNoArgIntFn>("ra_mlx_unregister_runtime");
    if (fn == nullptr) {
      return false;
    }
    return isRACSuccess(fn());
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::mlxIsBackendRegistered() {
  return Promise<bool>::async([]() {
    return callMLXNoArgBoolSymbol("ra_mlx_runtime_is_registered");
  });
}

} // namespace margelo::nitro::runanywhere

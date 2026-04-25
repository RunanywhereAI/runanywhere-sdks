/**
 * HybridRunAnywhereCore+Solutions.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// Solutions Runtime
// ============================================================================
// Solutions Runtime (rac/solutions/rac_solution.h) — T4.7 / T4.8
//
// Direct 1:1 mapping to the C ABI. Handles round-trip through a `double`
// so the JS side can hold a stable reference (Nitro doesn't yet support
// 64-bit integers in bridge types — the same pattern is used by
// `getVoiceAgentHandle` / `getLLMHandle`).
// ============================================================================

namespace {

inline double solutionHandleToDouble(rac_solution_handle_t handle) {
    // Pointer round-trip: intptr_t -> uint64 -> double. A JS `number` holds
    // 53-bit integer precision, which is enough for every pointer we see on
    // current mobile hardware.
    return static_cast<double>(reinterpret_cast<uintptr_t>(handle));
}

inline rac_solution_handle_t solutionHandleFromDouble(double handle) {
    return reinterpret_cast<rac_solution_handle_t>(
        static_cast<uintptr_t>(static_cast<uint64_t>(handle)));
}

} // namespace

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::solutionCreateFromProto(
    const std::string& configBytesBase64) {
    return Promise<double>::async([configBytesBase64]() -> double {
        const auto bytes = base64Decode(configBytesBase64);
        if (bytes.empty()) {
            return 0.0;
        }
        rac_solution_handle_t handle = nullptr;
        const rac_result_t rc = rac_solution_create_from_proto(
            bytes.data(), bytes.size(), &handle);
        if (rc != RAC_SUCCESS || handle == nullptr) {
            return 0.0;
        }
        return solutionHandleToDouble(handle);
    });
}

std::shared_ptr<Promise<double>> HybridRunAnywhereCore::solutionCreateFromYaml(
    const std::string& yamlText) {
    return Promise<double>::async([yamlText]() -> double {
        rac_solution_handle_t handle = nullptr;
        const rac_result_t rc =
            rac_solution_create_from_yaml(yamlText.c_str(), &handle);
        if (rc != RAC_SUCCESS || handle == nullptr) {
            return 0.0;
        }
        return solutionHandleToDouble(handle);
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::solutionStart(double handle) {
    return Promise<bool>::async([handle]() -> bool {
        auto h = solutionHandleFromDouble(handle);
        if (!h) return false;
        return rac_solution_start(h) == RAC_SUCCESS;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::solutionStop(double handle) {
    return Promise<bool>::async([handle]() -> bool {
        auto h = solutionHandleFromDouble(handle);
        if (!h) return false;
        return rac_solution_stop(h) == RAC_SUCCESS;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::solutionCancel(double handle) {
    return Promise<bool>::async([handle]() -> bool {
        auto h = solutionHandleFromDouble(handle);
        if (!h) return false;
        return rac_solution_cancel(h) == RAC_SUCCESS;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::solutionFeed(
    double handle, const std::string& item) {
    return Promise<bool>::async([handle, item]() -> bool {
        auto h = solutionHandleFromDouble(handle);
        if (!h) return false;
        return rac_solution_feed(h, item.c_str()) == RAC_SUCCESS;
    });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::solutionCloseInput(double handle) {
    return Promise<bool>::async([handle]() -> bool {
        auto h = solutionHandleFromDouble(handle);
        if (!h) return false;
        return rac_solution_close_input(h) == RAC_SUCCESS;
    });
}

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::solutionDestroy(double handle) {
    return Promise<void>::async([handle]() {
        auto h = solutionHandleFromDouble(handle);
        if (h != nullptr) {
            rac_solution_destroy(h);
        }
    });
}

} // namespace margelo::nitro::runanywhere

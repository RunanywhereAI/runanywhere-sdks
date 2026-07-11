/**
 * @file qhexrt_device_capability.cpp
 * @brief QHexRT-scoped facade over the compatibility commons NPU probe.
 *
 * Commons retains the originally published rac_npu_* ABI for same-version
 * source/binary compatibility. QHexRT's newer engine-scoped names delegate to
 * that implementation so SoC mappings and serialized capability bytes cannot
 * drift between the two public surfaces.
 */

#include <cstring>

#include "rac/infrastructure/device/rac_npu_capability.h"
#include "rac/qhexrt/rac_qhexrt.h"

static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN) ==
              static_cast<int32_t>(RAC_HEXAGON_ARCH_UNKNOWN));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V68) ==
              static_cast<int32_t>(RAC_HEXAGON_ARCH_V68));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V69) ==
              static_cast<int32_t>(RAC_HEXAGON_ARCH_V69));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V73) ==
              static_cast<int32_t>(RAC_HEXAGON_ARCH_V73));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V75) ==
              static_cast<int32_t>(RAC_HEXAGON_ARCH_V75));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V79) ==
              static_cast<int32_t>(RAC_HEXAGON_ARCH_V79));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V81) ==
              static_cast<int32_t>(RAC_HEXAGON_ARCH_V81));

extern "C" {

rac_bool_t rac_qhexrt_arch_is_supported(rac_qhexrt_hexagon_arch_t arch) {
    switch (arch) {
        case RAC_QHEXRT_HEXAGON_ARCH_V75:
        case RAC_QHEXRT_HEXAGON_ARCH_V79:
        case RAC_QHEXRT_HEXAGON_ARCH_V81:
            return RAC_TRUE;
        case RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN:
        case RAC_QHEXRT_HEXAGON_ARCH_V68:
        case RAC_QHEXRT_HEXAGON_ARCH_V69:
        case RAC_QHEXRT_HEXAGON_ARCH_V73:
        default:
            return RAC_FALSE;
    }
}

const char* rac_qhexrt_arch_name(rac_qhexrt_hexagon_arch_t arch) {
    return rac_hexagon_arch_name(static_cast<rac_hexagon_arch_t>(arch));
}

rac_result_t rac_qhexrt_probe(rac_qhexrt_device_info_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_npu_info_t legacy{};
    const rac_result_t probe_rc = rac_npu_probe(&legacy);
    if (probe_rc != RAC_SUCCESS) {
        return probe_rc;
    }

    std::memset(out, 0, sizeof(*out));
    std::memcpy(out->soc_model, legacy.soc_model, sizeof(out->soc_model));
    out->soc_id = legacy.soc_id;
    out->hexagon_arch = static_cast<rac_qhexrt_hexagon_arch_t>(legacy.hexagon_arch);
    out->supported = legacy.qhexrt_supported;
    return RAC_SUCCESS;
}

rac_result_t rac_qhexrt_probe_proto(rac_proto_buffer_t* out_capability) {
    return rac_npu_probe_proto(out_capability);
}

}  // extern "C"

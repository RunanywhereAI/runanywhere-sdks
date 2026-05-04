/**
 * HybridRunAnywhereCore+Hardware.cpp
 *
 * Hardware profile bridge backed by the commons proto ABI.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

namespace margelo::nitro::runanywhere {

namespace {

using HardwareProfileGetFn = rac_result_t (*)(uint8_t**, size_t*);
using HardwareProfileFreeFn = void (*)(uint8_t*);

std::shared_ptr<ArrayBuffer> emptyHardwareProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

} // namespace

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::hardwareProfileProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() {
        auto getProfile = proto_compat::symbol<HardwareProfileGetFn>(
            "rac_hardware_profile_get");
        auto freeProfile = proto_compat::symbol<HardwareProfileFreeFn>(
            "rac_hardware_profile_free");

        if (!getProfile || !freeProfile) {
            LOGE("hardwareProfileProto: hardware profile ABI unavailable");
            return emptyHardwareProtoBuffer();
        }

        uint8_t* bytes = nullptr;
        size_t size = 0;
        rac_result_t rc = getProfile(&bytes, &size);
        if (rc != RAC_SUCCESS) {
            LOGE("hardwareProfileProto: rac_hardware_profile_get failed: %d", rc);
            if (bytes) {
                freeProfile(bytes);
            }
            return emptyHardwareProtoBuffer();
        }

        if (!bytes || size == 0) {
            if (bytes) {
                freeProfile(bytes);
            }
            return emptyHardwareProtoBuffer();
        }

        auto buffer = ArrayBuffer::copy(bytes, size);
        freeProfile(bytes);
        return buffer;
    });
}

} // namespace margelo::nitro::runanywhere

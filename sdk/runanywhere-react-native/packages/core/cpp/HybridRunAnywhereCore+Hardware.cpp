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
using HardwareSetAcceleratorPreferenceFn = rac_result_t (*)(int);

std::shared_ptr<ArrayBuffer> emptyHardwareProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

// NOTE: commons exposes only the int-based `rac_hardware_set_accelerator_preference(int)`
// ABI — there is no `rac_hardware_set_accelerator_preference_proto` byte-passthrough yet.
// Until commons adds that ABI, this bridge decodes the JS-side proto bytes locally to
// extract the preference int, then delegates to the int ABI. The codec below is limited
// to the two fields of HardwareAcceleratorPreferenceRequest / HardwareAcceleratorPreferenceResult
// and is functionally correct (unknown fields are skipped per proto3 rules; bytes are
// snapshotted into the async lambda so there is no UAF). This is intentional divergence
// from the commons proto-byte pass-through pattern used by every other bridge; adding the
// commons proto ABI is tracked as a separate future enhancement.

// Decode a single proto varint starting at `cursor`. Returns false on malformed
// input or buffer overrun. Matches the wire format used by
// runanywhere.v1.HardwareAcceleratorPreferenceRequest.preference (enum).
bool readProtoVarint(const uint8_t* data, size_t size, size_t& cursor, uint64_t& value) {
    value = 0;
    uint32_t shift = 0;
    while (cursor < size) {
        uint8_t byte = data[cursor++];
        value |= static_cast<uint64_t>(byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) {
            return true;
        }
        shift += 7;
        if (shift >= 64) {
            return false;
        }
    }
    return false;
}

// Parse `HardwareAcceleratorPreferenceRequest`. The message contains a single
// AccelerationPreference enum at field 1 (tag = 0x08, varint). Missing/empty
// payload maps to ACCELERATION_PREFERENCE_UNSPECIFIED = 0. Unknown fields are
// skipped per proto3 rules.
bool parseAcceleratorPreferenceRequest(const uint8_t* data, size_t size, int& outPreference) {
    outPreference = 0;
    if (!data || size == 0) {
        return true;
    }
    size_t cursor = 0;
    while (cursor < size) {
        uint64_t tag = 0;
        if (!readProtoVarint(data, size, cursor, tag)) {
            return false;
        }
        uint32_t fieldNumber = static_cast<uint32_t>(tag >> 3);
        uint32_t wireType = static_cast<uint32_t>(tag & 0x7);
        if (fieldNumber == 1 && wireType == 0) {
            uint64_t value = 0;
            if (!readProtoVarint(data, size, cursor, value)) {
                return false;
            }
            outPreference = static_cast<int>(value);
            continue;
        }
        // Skip unknown field
        switch (wireType) {
            case 0: {
                uint64_t skip = 0;
                if (!readProtoVarint(data, size, cursor, skip)) {
                    return false;
                }
                break;
            }
            case 1: {
                if (cursor + 8 > size) return false;
                cursor += 8;
                break;
            }
            case 2: {
                uint64_t length = 0;
                if (!readProtoVarint(data, size, cursor, length)) {
                    return false;
                }
                if (cursor + length > size) return false;
                cursor += static_cast<size_t>(length);
                break;
            }
            case 5: {
                if (cursor + 4 > size) return false;
                cursor += 4;
                break;
            }
            default:
                return false;
        }
    }
    return true;
}

// Serialize `HardwareAcceleratorPreferenceResult { bool success; string error_message; }`.
// proto3 defaults (success=false, empty error_message) are omitted.
std::vector<uint8_t> encodeAcceleratorPreferenceResult(bool success,
                                                      const std::string& errorMessage) {
    std::vector<uint8_t> out;
    out.reserve(4 + errorMessage.size());
    if (success) {
        out.push_back(0x08);  // field 1 (success), wire type 0 (varint)
        out.push_back(0x01);
    }
    if (!errorMessage.empty()) {
        out.push_back(0x12);  // field 2 (error_message), wire type 2 (length-delimited)
        uint64_t length = errorMessage.size();
        while (length > 0x7F) {
            out.push_back(static_cast<uint8_t>((length & 0x7F) | 0x80));
            length >>= 7;
        }
        out.push_back(static_cast<uint8_t>(length));
        out.insert(out.end(), errorMessage.begin(), errorMessage.end());
    }
    return out;
}

std::shared_ptr<ArrayBuffer> buildPreferenceResponse(bool success,
                                                    const std::string& errorMessage) {
    auto bytes = encodeAcceleratorPreferenceResult(success, errorMessage);
    if (bytes.empty()) {
        // Non-empty response required — emit a single zero-length varint so
        // callers can still decode deterministically.
        return emptyHardwareProtoBuffer();
    }
    return ArrayBuffer::copy(bytes.data(), bytes.size());
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

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::setAcceleratorPreferenceProto(
    const std::shared_ptr<ArrayBuffer>& requestBytes) {
    std::vector<uint8_t> bytes;
    if (requestBytes) {
        uint8_t* data = requestBytes->data();
        size_t size = requestBytes->size();
        if (data && size > 0) {
            bytes.assign(data, data + size);
        }
    }

    return Promise<std::shared_ptr<ArrayBuffer>>::async([bytes = std::move(bytes)]() {
        int preference = 0;
        if (!parseAcceleratorPreferenceRequest(bytes.data(), bytes.size(), preference)) {
            LOGE("setAcceleratorPreferenceProto: malformed request bytes");
            return buildPreferenceResponse(false, "Malformed HardwareAcceleratorPreferenceRequest");
        }

        auto fn = proto_compat::symbol<HardwareSetAcceleratorPreferenceFn>(
            "rac_hardware_set_accelerator_preference");
        if (!fn) {
            LOGE("setAcceleratorPreferenceProto: rac_hardware_set_accelerator_preference unavailable");
            return buildPreferenceResponse(false,
                "rac_hardware_set_accelerator_preference symbol unavailable");
        }

        rac_result_t rc = fn(preference);
        if (rc != RAC_SUCCESS) {
            LOGE("setAcceleratorPreferenceProto: rac_hardware_set_accelerator_preference failed: %d", rc);
            return buildPreferenceResponse(false,
                std::string("rac_hardware_set_accelerator_preference failed: ") +
                std::to_string(rc));
        }

        return buildPreferenceResponse(true, {});
    });
}

} // namespace margelo::nitro::runanywhere

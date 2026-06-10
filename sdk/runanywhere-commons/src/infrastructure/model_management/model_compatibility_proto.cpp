/**
 * @file model_compatibility_proto.cpp
 * @brief Proto-byte C ABI for model compatibility checks.
 *
 * Wraps rac_model_check_compatibility() with the canonical
 * runanywhere.v1.ModelCompatibilityRequest /
 * runanywhere.v1.ModelCompatibilityResult message contracts so SDK
 * bridges (RN CompatibilityBridge, Web ModelManager, Kotlin compat path)
 * can stop reaching for the struct ABI.
 */

#include <cstdint>
#include <cstdio>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_compatibility.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

#define LOG_CAT "ModelCompatibilityProto"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

void populate_result(runanywhere::v1::ModelCompatibilityResult* result,
                     const rac_model_compatibility_result_t& source, const std::string& model_id) {
    result->set_model_id(model_id);
    result->set_is_compatible(source.is_compatible == RAC_TRUE);
    result->set_can_run(source.can_run == RAC_TRUE);
    result->set_can_fit(source.can_fit == RAC_TRUE);
    result->set_required_memory_bytes(source.required_memory);
    result->set_available_memory_bytes(source.available_memory);
    result->set_required_storage_bytes(source.required_storage);
    result->set_available_storage_bytes(source.available_storage);

    if (source.can_run != RAC_TRUE) {
        char buffer[160];
        std::snprintf(buffer, sizeof(buffer),
                      "insufficient RAM: requires %lld bytes, %lld available",
                      static_cast<long long>(source.required_memory),
                      static_cast<long long>(source.available_memory));
        result->add_reasons(buffer);
    }
    if (source.can_fit != RAC_TRUE) {
        char buffer[160];
        std::snprintf(buffer, sizeof(buffer),
                      "insufficient storage: requires %lld bytes, %lld available",
                      static_cast<long long>(source.required_storage),
                      static_cast<long long>(source.available_storage));
        result->add_reasons(buffer);
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" rac_result_t rac_model_compatibility_check_proto(const uint8_t* request_bytes,
                                                            size_t request_size,
                                                            rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(request_bytes, request_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "ModelCompatibilityRequest bytes are invalid");
    }

    runanywhere::v1::ModelCompatibilityRequest request;
    if (request_size > 0 && !request.ParseFromArray(parse_data(request_bytes, request_size),
                                                    static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ModelCompatibilityRequest");
    }

    runanywhere::v1::ModelCompatibilityResult proto_result;
    proto_result.set_model_id(request.model_id());

    if (request.model_id().empty()) {
        const char* msg = "ModelCompatibilityRequest.model_id is required";
        proto_result.set_error_code(static_cast<int32_t>(RAC_ERROR_INVALID_ARGUMENT));
        proto_result.set_error_message(msg);
        proto_result.add_reasons(msg);
        return copy_proto(proto_result, out_result);
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        const char* msg = "model registry is not initialized";
        proto_result.set_error_code(static_cast<int32_t>(RAC_ERROR_NOT_INITIALIZED));
        proto_result.set_error_message(msg);
        proto_result.add_reasons(msg);
        RAC_LOG_WARNING(LOG_CAT, "compat check called before registry init");
        return copy_proto(proto_result, out_result);
    }

    rac_model_compatibility_result_t struct_result = {};
    rac_result_t rc = rac_model_check_compatibility(
        registry, request.model_id().c_str(), request.available_ram_bytes(),
        request.available_storage_bytes(), &struct_result);
    if (rc != RAC_SUCCESS) {
        const char* msg = rac_error_message(rc);
        proto_result.set_error_code(static_cast<int32_t>(rc));
        proto_result.set_error_message(msg ? msg : "compatibility check failed");
        if (msg && msg[0] != '\0')
            proto_result.add_reasons(msg);
        return copy_proto(proto_result, out_result);
    }

    populate_result(&proto_result, struct_result, request.model_id());
    return copy_proto(proto_result, out_result);
#endif
}

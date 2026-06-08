/**
 * @file model_registry_fetch_assignments_proto.cpp
 * @brief Proto-byte C ABI for the FetchAssignments registry path.
 *
 * Wraps rac_model_registry_fetch_assignments() so SDK bridges (RN, Web,
 * Kotlin JNI) can replace per-SDK JSON shims with one canonical
 * proto-byte call. The platform adapter still owns HTTP transport via
 * rac_model_assignment_fetch(); this file converts struct results
 * to runanywhere.v1.ModelRegistryFetchAssignmentsResult bytes by
 * leveraging the registry's existing list_proto serialization path.
 */

#include <chrono>
#include <cstdint>
#include <cstring>
#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

#define LOG_CAT "ModelRegistryFetchAssignmentsProto"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

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

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" rac_result_t rac_model_registry_fetch_assignments_proto(const uint8_t* request_bytes,
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
                                          "ModelRegistryFetchAssignmentsRequest bytes are invalid");
    }

    runanywhere::v1::ModelRegistryFetchAssignmentsRequest request;
    if (request_size > 0 && !request.ParseFromArray(parse_data(request_bytes, request_size),
                                                    static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ModelRegistryFetchAssignmentsRequest");
    }

    runanywhere::v1::ModelRegistryFetchAssignmentsResult proto_result;

    const rac_bool_t force_refresh = request.force_refresh() ? RAC_TRUE : RAC_FALSE;

    // Phase 1: trigger the assignment fetch through the platform adapter.
    // rac_model_registry_fetch_assignments() handles caching, HTTP, and
    // populates the global model registry.  Discard the struct array — we
    // re-serialize via the registry's proto path below to capture full
    // ModelInfo fields (artifacts, expected files, metadata) that the
    // legacy struct cannot represent.
    rac_model_info_t** models = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_model_registry_fetch_assignments(force_refresh, &models, &count);
    if (models)
        rac_model_info_array_free(models, count);

    if (rc != RAC_SUCCESS) {
        const char* msg = rac_error_message(rc);
        proto_result.set_success(false);
        proto_result.set_error_code(static_cast<int32_t>(rc));
        proto_result.set_error_message(msg ? msg : "fetch assignments failed");
        proto_result.set_fetched_at_unix_ms(now_ms());
        RAC_LOG_WARNING(LOG_CAT, "fetch returned %d", rc);
        return copy_proto(proto_result, out_result);
    }

    // Phase 2: ask the registry to enumerate the canonical proto snapshots
    // it just persisted.  This reuses the rac_model_registry_list_proto
    // implementation (artifact info, metadata, expected files) so the
    // result mirrors what an SDK querying the registry directly would see.
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry) {
        uint8_t* list_bytes = nullptr;
        size_t list_size = 0;
        rac_result_t list_rc = rac_model_registry_list_proto(registry, &list_bytes, &list_size);
        if (list_rc == RAC_SUCCESS && list_bytes && list_size > 0) {
            runanywhere::v1::ModelInfoList list;
            if (list.ParseFromArray(list_bytes, static_cast<int>(list_size))) {
                *proto_result.mutable_models() = std::move(list);
            }
        }
        rac_model_registry_proto_free(list_bytes);
    }

    proto_result.set_success(true);
    proto_result.set_model_count(static_cast<int32_t>(count));
    proto_result.set_fetched_at_unix_ms(now_ms());

    RAC_LOG_INFO(LOG_CAT, "fetched %zu assignments via proto ABI", count);
    return copy_proto(proto_result, out_result);
#endif
}

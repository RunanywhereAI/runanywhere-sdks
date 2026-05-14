/**
 * @file rac_proto_buffer.cpp
 * @brief Shared C ABI ownership helpers for serialized proto byte buffers.
 */

#include "rac/foundation/rac_proto_buffer.h"

#include <cstring>
#include <limits>

namespace {

void reset_fields(rac_proto_buffer_t* buffer) {
    buffer->data = nullptr;
    buffer->size = 0;
    buffer->status = RAC_SUCCESS;
    buffer->error_message = nullptr;
}

void release_fields(rac_proto_buffer_t* buffer) {
    rac_free(buffer->data);
    rac_free(buffer->error_message);
    reset_fields(buffer);
}

}  // namespace

extern "C" {

rac_result_t rac_proto_bytes_validate(const uint8_t* data, size_t size) {
    if (!data && size != 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (size > static_cast<size_t>(std::numeric_limits<int>::max())) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return RAC_SUCCESS;
}

const void* rac_proto_bytes_data_or_empty(const uint8_t* data, size_t size) {
    static const uint8_t kEmptyProtoSentinel = 0;
    return size == 0 ? static_cast<const void*>(&kEmptyProtoSentinel)
                     : static_cast<const void*>(data);
}

void rac_proto_buffer_init(rac_proto_buffer_t* buffer) {
    if (!buffer) {
        return;
    }
    reset_fields(buffer);
}

rac_result_t rac_proto_buffer_copy(const uint8_t* data, size_t size,
                                   rac_proto_buffer_t* out_buffer) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    release_fields(out_buffer);

    rac_result_t validation = rac_proto_bytes_validate(data, size);
    if (validation != RAC_SUCCESS) {
        out_buffer->status = validation;
        return out_buffer->status;
    }

    const size_t alloc_size = size == 0 ? 1U : size;
    uint8_t* owned = static_cast<uint8_t*>(rac_alloc(alloc_size));
    if (!owned) {
        out_buffer->status = RAC_ERROR_OUT_OF_MEMORY;
        return out_buffer->status;
    }

    if (size == 0) {
        owned[0] = 0;
    } else {
        std::memcpy(owned, data, size);
    }

    out_buffer->data = owned;
    out_buffer->size = size;
    out_buffer->status = RAC_SUCCESS;
    return RAC_SUCCESS;
}

rac_result_t rac_proto_buffer_take_data(rac_proto_buffer_t* buffer, uint8_t** data_out,
                                        size_t* size_out) {
    if (!buffer || !data_out || !size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *data_out = nullptr;
    *size_out = 0;

    if (buffer->status != RAC_SUCCESS) {
        return buffer->status;
    }

    *data_out = buffer->data;
    *size_out = buffer->size;
    buffer->data = nullptr;
    buffer->size = 0;
    rac_free(buffer->error_message);
    buffer->error_message = nullptr;
    buffer->status = RAC_SUCCESS;
    return RAC_SUCCESS;
}

rac_result_t rac_proto_buffer_set_error(rac_proto_buffer_t* buffer, rac_result_t status,
                                        const char* error_message) {
    if (!buffer || RAC_SUCCEEDED(status)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    release_fields(buffer);
    buffer->status = status;
    if (error_message) {
        buffer->error_message = rac_strdup(error_message);
        if (!buffer->error_message) {
            buffer->status = RAC_ERROR_OUT_OF_MEMORY;
            return buffer->status;
        }
    }
    return status;
}

void rac_proto_buffer_free(rac_proto_buffer_t* buffer) {
    if (!buffer) {
        return;
    }
    release_fields(buffer);
}

rac_result_t rac_proto_buffer_copy_to_raw(const uint8_t* data, size_t size, uint8_t** data_out,
                                          size_t* size_out) {
    if (!data_out || !size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    *data_out = nullptr;
    *size_out = 0;

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_proto_buffer_copy(data, size, &buffer);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rc = rac_proto_buffer_take_data(&buffer, data_out, size_out);
    rac_proto_buffer_free(&buffer);
    return rc;
}

void rac_proto_buffer_free_data(uint8_t* data) {
    rac_free(data);
}

}  // extern "C"

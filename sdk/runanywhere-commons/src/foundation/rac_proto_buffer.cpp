/**
 * @file rac_proto_buffer.cpp
 * @brief Shared C ABI ownership helpers for serialized proto byte buffers.
 */

#include "rac/foundation/rac_proto_buffer.h"

#include <cstring>

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

void rac_proto_buffer_init(rac_proto_buffer_t* buffer) {
    if (!buffer) {
        return;
    }
    reset_fields(buffer);
}

rac_result_t rac_proto_buffer_copy(const uint8_t* data,
                                   size_t size,
                                   rac_proto_buffer_t* out_buffer) {
    if (!out_buffer) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    release_fields(out_buffer);

    if (!data && size != 0) {
        out_buffer->status = RAC_ERROR_INVALID_ARGUMENT;
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

rac_result_t rac_proto_buffer_set_error(rac_proto_buffer_t* buffer,
                                        rac_result_t status,
                                        const char* error_message) {
    if (!buffer || status == RAC_SUCCESS) {
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

rac_result_t rac_proto_buffer_copy_to_raw(const uint8_t* data,
                                          size_t size,
                                          uint8_t** data_out,
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

    *data_out = buffer.data;
    *size_out = buffer.size;
    buffer.data = nullptr;
    buffer.size = 0;
    rac_proto_buffer_free(&buffer);
    return RAC_SUCCESS;
}

void rac_proto_buffer_free_data(uint8_t* data) {
    rac_free(data);
}

}  // extern "C"

#ifndef RAC_FOUNDATION_RAC_PROTO_MARSHAL_INTERNAL_H
#define RAC_FOUNDATION_RAC_PROTO_MARSHAL_INTERNAL_H

// Internal (not installed): shared proto-byte marshalling helpers used by the
// feature modules' proto ABIs (stt, tts, vad, voice_agent, embeddings,
// diffusion): validate / parse-pointer / serialize-into-buffer.
//
// Only include this inside a `#if defined(RAC_HAVE_PROTOBUF)` block — it pulls
// in <google/protobuf/message_lite.h>.

#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

#include "google/protobuf/message_lite.h"
#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace rac::proto {

// True if (bytes, size) is a usable proto input: non-null when non-empty, and
// size fits in the `int` that protobuf's ParseFromArray takes.
inline bool bytes_valid(const uint8_t* bytes, size_t size) {
    return (size == 0 || bytes != nullptr) &&
           size <= static_cast<size_t>(std::numeric_limits<int>::max());
}

// Stable non-null pointer for ParseFromArray (protobuf rejects a null data
// pointer even when size == 0).
inline const void* parse_bytes(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

// Serialize `message` into `out`. `serialize_error` is the failure context used
// if serialization fails.
inline rac_result_t copy_message(const google::protobuf::MessageLite& message,
                                 rac_proto_buffer_t* out, const char* serialize_error) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR, serialize_error);
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

// Record a decode error on `out` (input bytes failed to parse).
inline rac_result_t parse_error(rac_proto_buffer_t* out, const char* message) {
    return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR, message);
}

}  // namespace rac::proto

#endif  // RAC_FOUNDATION_RAC_PROTO_MARSHAL_INTERNAL_H

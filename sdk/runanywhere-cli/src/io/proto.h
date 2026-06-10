/**
 * @file proto.h
 * @brief rac_proto_buffer_t ⇄ protobuf message glue.
 *
 * Every lifecycle C ABI call returns serialized proto bytes in a
 * rac_proto_buffer_t with the canonical {data, size, status} convention.
 * parse_proto_buffer() checks the status envelope, parses, and ALWAYS frees
 * the buffer.
 */

#ifndef RCLI_IO_PROTO_H
#define RCLI_IO_PROTO_H

#include <string>

#include "rac/foundation/rac_proto_buffer.h"

#include "io/output.h"

namespace rcli::proto {

/**
 * Parse an out-buffer into `message`, freeing the buffer in all paths.
 * On failure returns false and fills `error` (when non-null) with the buffer's
 * error envelope or a parse diagnostic.
 */
template <typename Message>
bool parse_proto_buffer(rac_proto_buffer_t* buffer, Message* message, std::string* error) {
    bool ok = false;
    if (buffer->status != RAC_SUCCESS) {
        if (error) {
            *error = (buffer->error_message && buffer->error_message[0] != '\0')
                         ? buffer->error_message
                         : rcli::out::describe_result(buffer->status);
        }
    } else if (!message->ParseFromArray(buffer->data, static_cast<int>(buffer->size))) {
        if (error) {
            *error = "failed to parse " + std::string(Message::descriptor()->name()) + " bytes";
        }
    } else {
        ok = true;
    }
    rac_proto_buffer_free(buffer);
    return ok;
}

/** Serialize a request message into a byte string (proto3 never fails here). */
template <typename Message>
std::string serialize(const Message& message) {
    std::string bytes;
    message.SerializeToString(&bytes);
    return bytes;
}

}  // namespace rcli::proto

#endif  // RCLI_IO_PROTO_H

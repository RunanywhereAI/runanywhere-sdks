#ifndef RUNANYWHERE_ELECTRON_PROTO_BRIDGE_H
#define RUNANYWHERE_ELECTRON_PROTO_BRIDGE_H

#include <napi.h>

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

namespace rac_electron {

using ProtoUnaryFn = rac_result_t (*)(const uint8_t*, size_t, rac_proto_buffer_t*);
using ProtoHandleFn = rac_result_t (*)(rac_handle_t, const uint8_t*, size_t, rac_proto_buffer_t*);
using ProtoNoInputFn = rac_result_t (*)(rac_proto_buffer_t*);

using ProtoCall = std::function<rac_result_t(rac_proto_buffer_t*)>;
using ProtoStreamStart = std::function<rac_result_t(rac_proto_bytes_callback_fn, void*)>;
using LeaseRelease = std::function<void()>;

// The non-proto half of the same seam: `NativeWork` runs the blocking rac_* call
// on a libuv worker, `NativeResult` converts whatever it produced into JS on the
// event-loop thread once the work has finished.
using NativeWork = std::function<rac_result_t()>;
using NativeResult = std::function<Napi::Value(Napi::Env)>;

Napi::Error ProtoError(Napi::Env env, rac_result_t code, const std::string& context,
                       const char* commons_message);

void ThrowProtoError(Napi::Env env, rac_result_t code, const std::string& context);

Napi::Value RejectWithProtoError(Napi::Env env, rac_result_t code, const std::string& context);

bool ReadProtoBytes(const Napi::Value& value, std::vector<uint8_t>* out);

std::vector<uint8_t> RequireProtoBytes(const Napi::CallbackInfo& info, size_t index,
                                       const char* signature);

Napi::Promise RunProtoCall(Napi::Env env, std::string context, ProtoCall call,
                           LeaseRelease release_lease);

Napi::Promise RunProtoCall(Napi::Env env, std::string context, ProtoCall call);

Napi::Promise RunProtoUnary(Napi::Env env, std::string context, ProtoUnaryFn fn,
                            std::vector<uint8_t> request);

Napi::Promise RunProtoOnHandle(Napi::Env env, std::string context, ProtoHandleFn fn,
                               rac_handle_t handle, std::vector<uint8_t> request,
                               LeaseRelease release_lease);

Napi::Promise RunProtoStream(Napi::Env env, std::string context, ProtoStreamStart start,
                             Napi::Function on_event, LeaseRelease release_lease);

Napi::Promise RunNativeCall(Napi::Env env, std::string context, NativeWork work, NativeResult build,
                            LeaseRelease release_lease);

Napi::Promise RunNativeCall(Napi::Env env, std::string context, NativeWork work,
                            NativeResult build);

Napi::Promise RunNativeCall(Napi::Env env, std::string context, NativeWork work);

}  // namespace rac_electron

#endif  // RUNANYWHERE_ELECTRON_PROTO_BRIDGE_H

#include "proto_bridge.h"

#include <atomic>
#include <memory>
#include <thread>
#include <utility>

#include "rac/core/rac_error_proto.h"

namespace rac_electron {
namespace {

constexpr size_t kStreamQueueCapacity = 512;

int PositiveErrorCode(rac_result_t code) {
    const int value = static_cast<int>(code);
    return value < 0 ? -value : value;
}

std::string DescribeFailure(const std::string& context, rac_result_t code,
                            const char* commons_message) {
    std::string message = context + " failed: " + std::to_string(static_cast<int>(code));
    if (commons_message != nullptr && *commons_message != '\0') {
        message += " (";
        message += commons_message;
        message += ")";
    }
    return message;
}

Napi::Value SerializedSdkError(Napi::Env env, rac_result_t code) {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t status = rac_result_to_proto_error(code, &buffer);
    Napi::Value bytes = env.Undefined();
    if (status == RAC_SUCCESS && buffer.data != nullptr && buffer.size > 0) {
        bytes = Napi::Buffer<uint8_t>::Copy(env, buffer.data, buffer.size);
    }
    rac_proto_buffer_free(&buffer);
    return bytes;
}

struct ProtoOutcome {
    bool ok = false;
    rac_result_t code = RAC_SUCCESS;
    std::vector<uint8_t> bytes;
    std::string message;
};

ProtoOutcome Consume(rac_proto_buffer_t* buffer, rac_result_t call_status,
                     const std::string& context) {
    ProtoOutcome outcome;
    if (call_status != RAC_SUCCESS && buffer->status == RAC_SUCCESS) {
        buffer->status = call_status;
    }
    if (buffer->status == RAC_SUCCESS) {
        outcome.ok = true;
        if (buffer->data != nullptr && buffer->size > 0) {
            outcome.bytes.assign(buffer->data, buffer->data + buffer->size);
        }
    } else {
        outcome.code = buffer->status;
        outcome.message = DescribeFailure(context, buffer->status, buffer->error_message);
    }
    rac_proto_buffer_free(buffer);
    return outcome;
}

class LeaseHolder {
   public:
    explicit LeaseHolder(LeaseRelease release) : release_(std::move(release)) {}

    LeaseHolder(const LeaseHolder&) = delete;
    LeaseHolder& operator=(const LeaseHolder&) = delete;

    ~LeaseHolder() { Release(); }

    void Release() {
        if (released_.exchange(true))
            return;
        if (release_)
            release_();
    }

   private:
    LeaseRelease release_;
    std::atomic<bool> released_{false};
};

class ProtoCallWorker : public Napi::AsyncWorker {
   public:
    ProtoCallWorker(Napi::Env env, std::string context, ProtoCall call, LeaseRelease release_lease)
        : Napi::AsyncWorker(env),
          deferred_(Napi::Promise::Deferred::New(env)),
          context_(std::move(context)),
          call_(std::move(call)),
          lease_(std::make_unique<LeaseHolder>(std::move(release_lease))) {}

    Napi::Promise Promise() { return deferred_.Promise(); }

    void Execute() override {
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const rac_result_t status = call_(&out);
        outcome_ = Consume(&out, status, context_);
        lease_->Release();
    }

    void OnOK() override {
        Napi::Env env = Env();
        Napi::HandleScope scope(env);
        if (outcome_.ok) {
            deferred_.Resolve(
                Napi::Buffer<uint8_t>::Copy(env, outcome_.bytes.data(), outcome_.bytes.size()));
        } else {
            deferred_.Reject(ProtoError(env, outcome_.code, context_, nullptr).Value());
        }
    }

    void OnError(const Napi::Error& error) override {
        lease_->Release();
        Napi::HandleScope scope(Env());
        deferred_.Reject(error.Value());
    }

   private:
    Napi::Promise::Deferred deferred_;
    std::string context_;
    ProtoCall call_;
    std::unique_ptr<LeaseHolder> lease_;
    ProtoOutcome outcome_;
};

class NativeCallWorker : public Napi::AsyncWorker {
   public:
    NativeCallWorker(Napi::Env env, std::string context, NativeWork work, NativeResult build,
                     LeaseRelease release_lease)
        : Napi::AsyncWorker(env),
          deferred_(Napi::Promise::Deferred::New(env)),
          context_(std::move(context)),
          work_(std::move(work)),
          build_(std::move(build)),
          lease_(std::make_unique<LeaseHolder>(std::move(release_lease))) {}

    Napi::Promise Promise() { return deferred_.Promise(); }

    void Execute() override {
        status_ = work_();
        lease_->Release();
    }

    void OnOK() override {
        Napi::Env env = Env();
        Napi::HandleScope scope(env);
        if (status_ != RAC_SUCCESS) {
            deferred_.Reject(ProtoError(env, status_, context_, nullptr).Value());
            return;
        }
        // The result builder touches native memory the work left behind; a throw
        // here must reject rather than escape into the microtask checkpoint.
        try {
            deferred_.Resolve(build_ ? build_(env) : env.Undefined());
        } catch (const Napi::Error& error) {
            deferred_.Reject(error.Value());
        }
    }

    void OnError(const Napi::Error& error) override {
        lease_->Release();
        Napi::HandleScope scope(Env());
        deferred_.Reject(error.Value());
    }

   private:
    Napi::Promise::Deferred deferred_;
    std::string context_;
    NativeWork work_;
    NativeResult build_;
    std::unique_ptr<LeaseHolder> lease_;
    rac_result_t status_ = RAC_SUCCESS;
};

struct ProtoStreamSession {
    Napi::ThreadSafeFunction emit;
    Napi::Promise::Deferred deferred;
    std::thread runner;
    std::string context;
    ProtoStreamStart start;
    std::unique_ptr<LeaseHolder> lease;
    rac_result_t status = RAC_SUCCESS;

    explicit ProtoStreamSession(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

void ForwardStreamEvent(const uint8_t* bytes, size_t size, void* user_data) {
    auto* session = static_cast<ProtoStreamSession*>(user_data);
    if (session == nullptr || bytes == nullptr || size == 0)
        return;
    auto payload = std::make_shared<std::vector<uint8_t>>(bytes, bytes + size);
    session->emit.BlockingCall(
        new std::shared_ptr<std::vector<uint8_t>>(std::move(payload)),
        [](Napi::Env env, Napi::Function callback, std::shared_ptr<std::vector<uint8_t>>* held) {
            std::unique_ptr<std::shared_ptr<std::vector<uint8_t>>> owned(held);
            callback.Call({Napi::Buffer<uint8_t>::Copy(env, (*owned)->data(), (*owned)->size())});
        });
}

}  // namespace

Napi::Error ProtoError(Napi::Env env, rac_result_t code, const std::string& context,
                       const char* commons_message) {
    Napi::Error error = Napi::Error::New(env, DescribeFailure(context, code, commons_message));
    Napi::Object value = error.Value();
    value.Set("code", Napi::Number::New(env, PositiveErrorCode(code)));
    value.Set("cAbiCode", Napi::Number::New(env, static_cast<int>(code)));
    value.Set("sdkError", SerializedSdkError(env, code));
    return error;
}

void ThrowProtoError(Napi::Env env, rac_result_t code, const std::string& context) {
    ProtoError(env, code, context, nullptr).ThrowAsJavaScriptException();
}

Napi::Value RejectWithProtoError(Napi::Env env, rac_result_t code, const std::string& context) {
    Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
    deferred.Reject(ProtoError(env, code, context, nullptr).Value());
    return deferred.Promise();
}

bool ReadProtoBytes(const Napi::Value& value, std::vector<uint8_t>* out) {
    if (value.IsUndefined() || value.IsNull()) {
        out->clear();
        return true;
    }
    if (value.IsBuffer()) {
        Napi::Buffer<uint8_t> buffer = value.As<Napi::Buffer<uint8_t>>();
        out->assign(buffer.Data(), buffer.Data() + buffer.Length());
        return true;
    }
    if (!value.IsTypedArray())
        return false;
    Napi::TypedArray array = value.As<Napi::TypedArray>();
    if (array.TypedArrayType() != napi_uint8_array)
        return false;
    Napi::Uint8Array bytes = array.As<Napi::Uint8Array>();
    out->assign(bytes.Data(), bytes.Data() + bytes.ByteLength());
    return true;
}

std::vector<uint8_t> RequireProtoBytes(const Napi::CallbackInfo& info, size_t index,
                                       const char* signature) {
    std::vector<uint8_t> bytes;
    const Napi::Value value = info.Length() > index ? info[index] : info.Env().Undefined();
    if (!ReadProtoBytes(value, &bytes)) {
        throw Napi::TypeError::New(info.Env(), std::string(signature) +
                                                   " expects proto bytes at argument " +
                                                   std::to_string(index));
    }
    return bytes;
}

Napi::Promise RunProtoCall(Napi::Env env, std::string context, ProtoCall call,
                           LeaseRelease release_lease) {
    auto* worker =
        new ProtoCallWorker(env, std::move(context), std::move(call), std::move(release_lease));
    Napi::Promise promise = worker->Promise();
    try {
        worker->Queue();
    } catch (...) {
        delete worker;
        throw;
    }
    return promise;
}

Napi::Promise RunProtoCall(Napi::Env env, std::string context, ProtoCall call) {
    return RunProtoCall(env, std::move(context), std::move(call), nullptr);
}

Napi::Promise RunProtoUnary(Napi::Env env, std::string context, ProtoUnaryFn fn,
                            std::vector<uint8_t> request) {
    auto payload = std::make_shared<std::vector<uint8_t>>(std::move(request));
    return RunProtoCall(env, std::move(context), [fn, payload](rac_proto_buffer_t* out) {
        return fn(payload->empty() ? nullptr : payload->data(), payload->size(), out);
    });
}

Napi::Promise RunProtoOnHandle(Napi::Env env, std::string context, ProtoHandleFn fn,
                               rac_handle_t handle, std::vector<uint8_t> request,
                               LeaseRelease release_lease) {
    auto payload = std::make_shared<std::vector<uint8_t>>(std::move(request));
    return RunProtoCall(
        env, std::move(context),
        [fn, handle, payload](rac_proto_buffer_t* out) {
            return fn(handle, payload->empty() ? nullptr : payload->data(), payload->size(), out);
        },
        std::move(release_lease));
}

Napi::Promise RunNativeCall(Napi::Env env, std::string context, NativeWork work, NativeResult build,
                            LeaseRelease release_lease) {
    auto* worker = new NativeCallWorker(env, std::move(context), std::move(work), std::move(build),
                                        std::move(release_lease));
    Napi::Promise promise = worker->Promise();
    try {
        worker->Queue();
    } catch (...) {
        delete worker;
        throw;
    }
    return promise;
}

Napi::Promise RunNativeCall(Napi::Env env, std::string context, NativeWork work,
                            NativeResult build) {
    return RunNativeCall(env, std::move(context), std::move(work), std::move(build), nullptr);
}

Napi::Promise RunNativeCall(Napi::Env env, std::string context, NativeWork work) {
    return RunNativeCall(env, std::move(context), std::move(work), nullptr, nullptr);
}

Napi::Promise RunProtoStream(Napi::Env env, std::string context, ProtoStreamStart start,
                             Napi::Function on_event, LeaseRelease release_lease) {
    auto* session = new ProtoStreamSession(env);
    session->context = std::move(context);
    session->start = std::move(start);
    session->lease = std::make_unique<LeaseHolder>(std::move(release_lease));

    Napi::Promise promise = session->deferred.Promise();

    session->emit = Napi::ThreadSafeFunction::New(
        env, on_event, "runanywhere_proto_stream", kStreamQueueCapacity, 1,
        [session](Napi::Env finalizer_env) {
            if (session->runner.joinable())
                session->runner.join();
            session->lease->Release();
            Napi::HandleScope scope(finalizer_env);
            if (session->status == RAC_SUCCESS) {
                session->deferred.Resolve(finalizer_env.Undefined());
            } else {
                session->deferred.Reject(
                    ProtoError(finalizer_env, session->status, session->context, nullptr).Value());
            }
            delete session;
        });

    session->runner = std::thread([session]() {
        session->status = session->start(ForwardStreamEvent, session);
        session->emit.Release();
    });

    return promise;
}

}  // namespace rac_electron

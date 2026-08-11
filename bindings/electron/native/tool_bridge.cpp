// tool_bridge.cpp — the tool-calling half of the proto ABI.
//
// Commons owns the whole loop: prompt formatting, parsing, validation,
// execution ordering, the follow-up turn, and cancellation. This file only
// carries a trampoline so `rac_tool_calling_run_loop_proto` can reach a
// JavaScript executor, which is exactly the split Swift's
// RunAnywhere+ToolCalling.swift uses.
//
// The trampoline is synchronous by contract and the executor is a JS promise,
// so the run-loop thread parks on a condition variable while the event loop
// resolves it. Nothing blocks the event loop: the wait is on the worker.

#include "tool_bridge.h"

#include "proto_bridge.h"

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "rac/features/llm/rac_tool_calling.h"

namespace rac_electron {
namespace {

constexpr size_t kToolQueueCapacity = 64;

// Same budget Swift gives a tool executor. A wedged executor has to surface as
// a failed call rather than a run loop nobody can finish.
constexpr std::chrono::seconds kExecutorTimeout{120};

// One in-flight executor call. Shared because the run-loop thread may abandon
// it on timeout while the JS promise is still pending.
struct ExecuteSlot {
    std::mutex mu;
    std::condition_variable cv;
    bool done = false;
    bool ok = false;
    std::vector<uint8_t> result;
    std::string error;

    void settle(bool succeeded, std::vector<uint8_t> bytes, std::string message) {
        {
            std::lock_guard<std::mutex> lock(mu);
            if (done)
                return;
            done = true;
            ok = succeeded;
            result = std::move(bytes);
            error = std::move(message);
        }
        cv.notify_all();
    }
};

// A handle publication when `slot` is null, an executor request otherwise.
struct EmitJob {
    uint64_t handle = 0;
    std::vector<uint8_t> tool_call;
    std::shared_ptr<ExecuteSlot> slot;
};

struct RunLoopSession {
    Napi::ThreadSafeFunction emit;
    Napi::Promise::Deferred deferred;
    std::thread runner;
    std::vector<uint8_t> request;
    std::vector<uint8_t> result;
    std::string failure;
    rac_result_t status = RAC_SUCCESS;

    explicit RunLoopSession(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

void SettleFromReply(const std::shared_ptr<ExecuteSlot>& slot, const Napi::Value& value) {
    std::vector<uint8_t> bytes;
    if (!ReadProtoBytes(value, &bytes)) {
        slot->settle(false, {}, "tool executor did not return serialized ToolResult bytes");
        return;
    }
    slot->settle(true, std::move(bytes), {});
}

void EmitToJs(Napi::Env env, Napi::Function callback, EmitJob* raw) {
    std::unique_ptr<EmitJob> job(raw);
    Napi::Object event = Napi::Object::New(env);
    if (!job->slot) {
        event.Set("handle", Napi::Number::New(env, static_cast<double>(job->handle)));
        callback.Call({event});
        return;
    }

    std::shared_ptr<ExecuteSlot> slot = job->slot;
    event.Set("toolCall", Napi::Buffer<uint8_t>::Copy(env, job->tool_call.data(),
                                                      job->tool_call.size()));
    Napi::Value reply;
    try {
        reply = callback.Call({event});
    } catch (const Napi::Error& error) {
        slot->settle(false, {}, error.Message());
        return;
    }
    if (!reply.IsPromise()) {
        SettleFromReply(slot, reply);
        return;
    }
    Napi::Promise promise = reply.As<Napi::Promise>();
    Napi::Function on_ok = Napi::Function::New(env, [slot](const Napi::CallbackInfo& info) {
        SettleFromReply(slot, info.Length() > 0 ? info[0] : info.Env().Undefined());
    });
    Napi::Function on_error = Napi::Function::New(env, [slot](const Napi::CallbackInfo& info) {
        std::string message = "tool executor rejected";
        if (info.Length() > 0 && info[0].IsObject()) {
            const Napi::Value text = info[0].As<Napi::Object>().Get("message");
            if (text.IsString())
                message = text.As<Napi::String>().Utf8Value();
        }
        slot->settle(false, {}, message);
    });
    promise.Get("then").As<Napi::Function>().Call(promise, {on_ok, on_error});
}

rac_result_t ExecuteTool(const uint8_t* in_bytes, size_t in_size, rac_proto_buffer_t* out,
                         void* user_data) {
    rac_proto_buffer_init(out);
    auto* session = static_cast<RunLoopSession*>(user_data);
    if (session == nullptr)
        return rac_proto_buffer_set_error(out, RAC_ERROR_NULL_POINTER, "no run-loop session");

    auto slot = std::make_shared<ExecuteSlot>();
    auto* job = new EmitJob{0,
                            in_bytes != nullptr && in_size > 0
                                ? std::vector<uint8_t>(in_bytes, in_bytes + in_size)
                                : std::vector<uint8_t>(),
                            slot};
    if (session->emit.BlockingCall(job, EmitToJs) != napi_ok) {
        delete job;
        return rac_proto_buffer_set_error(out, RAC_ERROR_INTERNAL,
                                          "tool executor is no longer reachable");
    }

    std::unique_lock<std::mutex> lock(slot->mu);
    if (!slot->cv.wait_for(lock, kExecutorTimeout, [&slot] { return slot->done; })) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_TIMEOUT, "tool executor timed out");
    }
    if (!slot->ok)
        return rac_proto_buffer_set_error(out, RAC_ERROR_INTERNAL, slot->error.c_str());
    return rac_proto_buffer_copy(slot->result.data(), slot->result.size(), out);
}

// Commons calls this before its first generation so a cancel can race the loop.
// Non-blocking: the run loop must not wait on the event loop to make progress.
void PublishHandle(uint64_t handle, void* user_data) {
    auto* session = static_cast<RunLoopSession*>(user_data);
    if (session == nullptr)
        return;
    auto* job = new EmitJob{handle, {}, nullptr};
    if (session->emit.NonBlockingCall(job, EmitToJs) != napi_ok)
        delete job;
}

// toolRunLoopProto(requestBytes, onEvent) -> Promise<Buffer>. `onEvent` is
// called with `{ handle }` once, and with `{ toolCall }` per call commons
// wants executed; the latter must resolve to serialized ToolResult bytes.
Napi::Value ToolRunLoop(const Napi::CallbackInfo& info) {
    std::vector<uint8_t> request =
        RequireProtoBytes(info, 0, "toolRunLoopProto(requestBytes, onEvent)");
    if (info.Length() < 2 || !info[1].IsFunction()) {
        throw Napi::TypeError::New(info.Env(),
                                   "toolRunLoopProto(requestBytes, onEvent) expects a callback");
    }

    auto* session = new RunLoopSession(info.Env());
    session->request = std::move(request);
    Napi::Promise promise = session->deferred.Promise();

    session->emit = Napi::ThreadSafeFunction::New(
        info.Env(), info[1].As<Napi::Function>(), "runanywhere_tool_run_loop", kToolQueueCapacity,
        1, [session](Napi::Env finalizer_env) {
            if (session->runner.joinable())
                session->runner.join();
            Napi::HandleScope scope(finalizer_env);
            if (session->status == RAC_SUCCESS) {
                session->deferred.Resolve(Napi::Buffer<uint8_t>::Copy(
                    finalizer_env, session->result.data(), session->result.size()));
            } else {
                session->deferred.Reject(
                    ProtoError(finalizer_env, session->status, "tool_run_loop",
                               session->failure.empty() ? nullptr : session->failure.c_str())
                        .Value());
            }
            delete session;
        });

    session->runner = std::thread([session]() {
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        const rac_result_t rc = rac_tool_calling_run_loop_proto(
            session->request.empty() ? nullptr : session->request.data(), session->request.size(),
            ExecuteTool, session, PublishHandle, session, &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS)
            out.status = rc;
        session->status = out.status;
        if (out.status == RAC_SUCCESS) {
            if (out.data != nullptr && out.size > 0)
                session->result.assign(out.data, out.data + out.size);
        } else if (out.error_message != nullptr) {
            session->failure = out.error_message;
        }
        rac_proto_buffer_free(&out);
        session->emit.Release();
    });

    return promise;
}

Napi::Value ToolRunLoopCancel(const Napi::CallbackInfo& info) {
    if (info.Length() < 1 || !info[0].IsNumber())
        throw Napi::TypeError::New(info.Env(), "toolRunLoopCancelProto(handle) expects a number");
    const auto handle = static_cast<uint64_t>(info[0].As<Napi::Number>().Int64Value());
    rac_tool_calling_run_loop_cancel_proto(handle);
    return info.Env().Undefined();
}

}  // namespace

void RegisterToolBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("toolRunLoopProto", Napi::Function::New(env, ToolRunLoop));
    exports.Set("toolRunLoopCancelProto", Napi::Function::New(env, ToolRunLoopCancel));
}

}  // namespace rac_electron

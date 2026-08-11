// logging_bridge.cpp — level control and a record subscription over the commons
// logger.
//
// The level knob is commons' own: `rac_logger_set_min_level` is read by every
// RAC_LOG_* macro *before* it formats, so lowering it costs nothing and raising
// it genuinely stops the work rather than filtering afterwards.
//
// The subscription is shaped like the download-progress one in
// `download_bridge.cpp`: a single process-wide ThreadSafeFunction, unreferenced
// so an open subscription never keeps the process alive, and a NonBlockingCall
// so a slow consumer drops records instead of stalling the engine thread that
// emitted one.

#include "logging_bridge.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <string>

#include "rac/core/rac_logger.h"

namespace rac_electron {
namespace {

/** One record, copied off the emitting thread before it is queued. */
struct LogRecord {
    rac_log_level_t level;
    std::string category;
    std::string message;
    int64_t timestamp_unix_ms;
};

std::mutex g_mutex;
Napi::ThreadSafeFunction g_emit;
bool g_active = false;
// Commons' own stderr writer is toggled through rac_logger_set_stderr_always;
// this is the adapter half of the same switch, so "local logging off" silences
// both rather than half of them.
std::atomic<bool> g_local_sink{true};

const char* LevelName(rac_log_level_t level) {
    switch (level) {
        case RAC_LOG_TRACE: return "TRACE";
        case RAC_LOG_DEBUG: return "DEBUG";
        case RAC_LOG_INFO: return "INFO";
        case RAC_LOG_WARNING: return "WARN";
        case RAC_LOG_ERROR: return "ERROR";
        case RAC_LOG_FATAL: return "FATAL";
        default: return "?";
    }
}

int64_t NowUnixMs() {
    using std::chrono::duration_cast;
    using std::chrono::milliseconds;
    using std::chrono::system_clock;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

void Detach() {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_active) {
        return;
    }
    g_active = false;
    g_emit.Release();
}

Napi::Value SubscribeRecords(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsFunction()) {
        throw Napi::TypeError::New(env, "loggingSubscribe(onRecord) expects a function");
    }
    Detach();
    std::lock_guard<std::mutex> lock(g_mutex);
    g_emit = Napi::ThreadSafeFunction::New(env, info[0].As<Napi::Function>(),
                                           "runanywhere_log_records", 0, 1);
    g_emit.Unref(env);
    g_active = true;
    return env.Undefined();
}

Napi::Value UnsubscribeRecords(const Napi::CallbackInfo& info) {
    Detach();
    return info.Env().Undefined();
}

Napi::Value SetLevel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        throw Napi::TypeError::New(env, "loggingSetLevel(level) expects a number");
    }
    rac_logger_set_min_level(static_cast<rac_log_level_t>(info[0].As<Napi::Number>().Int32Value()));
    return env.Undefined();
}

Napi::Value GetLevel(const Napi::CallbackInfo& info) {
    return Napi::Number::New(info.Env(), static_cast<int32_t>(rac_logger_get_min_level()));
}

Napi::Value SetLocalEnabled(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsBoolean()) {
        throw Napi::TypeError::New(env, "loggingSetLocalEnabled(enabled) expects a boolean");
    }
    const bool enabled = info[0].As<Napi::Boolean>().Value();
    g_local_sink.store(enabled, std::memory_order_relaxed);
    rac_logger_set_stderr_always(enabled ? RAC_TRUE : RAC_FALSE);
    rac_logger_set_stderr_fallback(enabled ? RAC_TRUE : RAC_FALSE);
    return env.Undefined();
}

// Nothing buffers a record on this side — the local sink is an unbuffered
// fprintf and the subscriber queue is drained by the event loop — so a flush is
// only commons' own pending output.
Napi::Value Flush(const Napi::CallbackInfo& info) {
    std::fflush(stderr);
    return info.Env().Undefined();
}

}  // namespace

void ForwardLog(rac_log_level_t level, const char* category, const char* message) {
    const char* tag = category != nullptr ? category : "";
    const char* text = message != nullptr ? message : "";
    if (g_local_sink.load(std::memory_order_relaxed)) {
        fprintf(stderr, "[%s] %s: %s\n", LevelName(level), tag, text);
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_active) {
        return;
    }
    auto* record = new LogRecord{level, tag, text, NowUnixMs()};
    const napi_status status = g_emit.NonBlockingCall(
        record, [](Napi::Env env, Napi::Function callback, LogRecord* held) {
            Napi::Object entry = Napi::Object::New(env);
            entry.Set("level", Napi::Number::New(env, static_cast<int32_t>(held->level)));
            entry.Set("category", Napi::String::New(env, held->category));
            entry.Set("message", Napi::String::New(env, held->message));
            entry.Set("timestampUnixMs",
                      Napi::Number::New(env, static_cast<double>(held->timestamp_unix_ms)));
            callback.Call({entry});
            delete held;
        });
    if (status != napi_ok) {
        delete record;
    }
}

void RegisterLoggingBridge(Napi::Env env, Napi::Object exports) {
    exports.Set("loggingSetLevel", Napi::Function::New(env, SetLevel));
    exports.Set("loggingLevel", Napi::Function::New(env, GetLevel));
    exports.Set("loggingSetLocalEnabled", Napi::Function::New(env, SetLocalEnabled));
    exports.Set("loggingFlush", Napi::Function::New(env, Flush));
    exports.Set("loggingSubscribe", Napi::Function::New(env, SubscribeRecords));
    exports.Set("loggingUnsubscribe", Napi::Function::New(env, UnsubscribeRecords));
}

void ShutdownLoggingBridge() {
    Detach();
}

}  // namespace rac_electron

extern "C" void rac_electron_forward_log(rac_log_level_t level, const char* category,
                                         const char* message) {
    rac_electron::ForwardLog(level, category, message);
}

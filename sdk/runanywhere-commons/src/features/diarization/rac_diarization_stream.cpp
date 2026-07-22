/**
 * @file rac_diarization_stream.cpp
 * @brief Persistent proto-byte speaker-diarization stream sessions.
 */

#include "rac/features/diarization/rac_diarization_stream.h"

#include "diarization_internal.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

#include "features/common/rac_stream_registry_internal.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/features/diarization/rac_diarization_service.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "diarization.pb.h"
#include "errors.pb.h"
#endif

namespace {

std::mutex& registry_mutex() {
    static std::mutex mutex;
    return mutex;
}

struct CallbackSlot {
    rac_diarization_stream_proto_callback_fn callback = nullptr;
    void* user_data = nullptr;
};

struct StreamComponent {
    rac_handle_t lifecycle = nullptr;
    uint64_t owner_id = 0;
    bool accepting_sessions = true;
};

std::unordered_map<rac_handle_t, CallbackSlot>& callback_slots() {
    static std::unordered_map<rac_handle_t, CallbackSlot> slots;
    return slots;
}

std::unordered_map<rac_handle_t, StreamComponent>& stream_components() {
    static std::unordered_map<rac_handle_t, StreamComponent> components;
    return components;
}

std::atomic<uint64_t>& component_ids() {
    static std::atomic<uint64_t> ids{0};
    return ids;
}

struct CallbackInvocation {
    uint64_t epoch = 0;
    std::thread::id owner;
    CallbackInvocation* active_next = nullptr;
    CallbackInvocation* thread_previous = nullptr;
};

std::mutex& callback_tracker_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::condition_variable& callback_tracker_cv() {
    static std::condition_variable cv;
    return cv;
}

CallbackInvocation*& active_callbacks() {
    static CallbackInvocation* head = nullptr;
    return head;
}

uint64_t& next_callback_epoch() {
    static uint64_t epoch = 1;
    return epoch;
}

thread_local CallbackInvocation* g_current_callback = nullptr;

class CallbackInvocationGuard {
   public:
    CallbackInvocationGuard() = default;

    ~CallbackInvocationGuard() {
        if (!admitted_) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(callback_tracker_mutex());
            CallbackInvocation** link = &active_callbacks();
            while (*link && *link != &invocation_) {
                link = &(*link)->active_next;
            }
            if (*link == &invocation_) {
                *link = invocation_.active_next;
            }
            g_current_callback = invocation_.thread_previous;
        }
        callback_tracker_cv().notify_all();
    }

    void admit() {
        std::lock_guard<std::mutex> lock(callback_tracker_mutex());
        invocation_.epoch = next_callback_epoch()++;
        invocation_.owner = std::this_thread::get_id();
        invocation_.active_next = active_callbacks();
        invocation_.thread_previous = g_current_callback;
        active_callbacks() = &invocation_;
        g_current_callback = &invocation_;
        admitted_ = true;
    }

    CallbackInvocationGuard(const CallbackInvocationGuard&) = delete;
    CallbackInvocationGuard& operator=(const CallbackInvocationGuard&) = delete;

   private:
    CallbackInvocation invocation_;
    bool admitted_ = false;
};

#if defined(RAC_HAVE_PROTOBUF)

enum class Termination { kActive, kStop, kCancel };

struct StreamSession;

struct ProviderCallbackContext {
    std::weak_ptr<StreamSession> session;
};

struct StreamSession {
    uint64_t id = 0;
    rac_handle_t component = nullptr;
    rac_handle_t lifecycle = nullptr;
    rac_handle_t service = nullptr;
    rac_handle_t backend_stream = nullptr;
    rac_diarization_options_t options = RAC_DIARIZATION_OPTIONS_DEFAULT;
    runanywhere::v1::DiarizationAudioEncoding encoding =
        runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_F32_LE;
    std::unique_ptr<ProviderCallbackContext> callback_context;

    std::mutex mutex;
    std::condition_variable cv;
    Termination termination = Termination::kActive;
    bool drop_events = false;
    bool flushing = false;
    bool final_emitted = false;
    bool cleanup_deferred = false;
    bool cleanup_claimed = false;
    bool cleanup_finished = false;
    size_t feeds_in_flight = 0;
    size_t provider_callbacks_in_flight = 0;
    uint64_t next_seq = 0;
    rac_result_t callback_error = RAC_SUCCESS;
    runanywhere::v1::DiarizationResult last_snapshot;
    bool has_snapshot = false;
};

std::unordered_map<uint64_t, std::shared_ptr<StreamSession>>& sessions() {
    static std::unordered_map<uint64_t, std::shared_ptr<StreamSession>> value;
    return value;
}

rac::stream::SessionIdAllocator& session_ids() {
    static rac::stream::SessionIdAllocator ids;
    return ids;
}

thread_local uint64_t g_dispatching_session = 0;

int64_t now_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count();
}

int64_t now_ms() {
    return now_us() / 1000;
}

void finish_provider_callback(const std::shared_ptr<StreamSession>& session);
rac_result_t finalize_session(const std::shared_ptr<StreamSession>& session);
void maybe_finalize_deferred(const std::shared_ptr<StreamSession>& session);

bool callback_allowed_locked(const StreamSession& session) {
    return !session.drop_events &&
           (session.termination == Termination::kActive ||
            (session.termination == Termination::kStop && session.flushing));
}

void dispatch_event(const std::shared_ptr<StreamSession>& session,
                    runanywhere::v1::DiarizationStreamEventKind kind,
                    const runanywhere::v1::DiarizationResult* result,
                    rac_result_t error_code = RAC_SUCCESS, const char* error_message = nullptr) {
    runanywhere::v1::DiarizationStreamEvent event;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (!callback_allowed_locked(*session) &&
            kind != runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_ERROR) {
            return;
        }
        if (session->drop_events) {
            return;
        }
        event.set_session_id(session->id);
        event.set_seq(session->next_seq++);
    }
    event.set_timestamp_us(now_us());
    event.set_kind(kind);
    if (result) {
        event.mutable_result()->CopyFrom(*result);
    }
    if (error_code != RAC_SUCCESS || (error_message && error_message[0] != '\0')) {
        auto* error = event.mutable_error();
        const int32_t numeric = static_cast<int32_t>(error_code);
        error->set_code(static_cast<runanywhere::v1::ErrorCode>(numeric < 0 ? -numeric : numeric));
        error->set_category(runanywhere::v1::ERROR_CATEGORY_COMPONENT);
        error->set_message(error_message ? error_message : "speaker diarization failed");
        error->set_c_abi_code(numeric);
        error->set_timestamp_ms(now_ms());
        error->set_severity(runanywhere::v1::ERROR_SEVERITY_ERROR);
        error->set_component("diarization");
    }

    std::string bytes;
    if (!event.SerializeToString(&bytes)) {
        return;
    }

    CallbackSlot slot;
    CallbackInvocationGuard invocation;
    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        const auto it = callback_slots().find(session->component);
        if (it == callback_slots().end() || !it->second.callback) {
            return;
        }
        slot = it->second;
        // Admission is recorded before releasing the slot registry lock. An
        // unset followed by quiesce therefore cannot miss a callback that
        // already copied the callback/user_data pair.
        invocation.admit();
    }

    const uint64_t previous_session = g_dispatching_session;
    g_dispatching_session = session->id;
    slot.callback(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), slot.user_data);
    g_dispatching_session = previous_session;
    maybe_finalize_deferred(session);
}

void provider_callback(const rac_diarization_result_t* result, void* user_data) {
    auto* context = static_cast<ProviderCallbackContext*>(user_data);
    if (!context) {
        return;
    }
    const std::shared_ptr<StreamSession> session = context->session.lock();
    if (!session) {
        return;
    }

    bool final = false;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (!callback_allowed_locked(*session)) {
            return;
        }
        ++session->provider_callbacks_in_flight;
        final = session->flushing;
    }

    if (!result) {
        {
            std::lock_guard<std::mutex> lock(session->mutex);
            session->callback_error = RAC_ERROR_ENCODING_ERROR;
        }
        dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_ERROR, nullptr,
                       RAC_ERROR_ENCODING_ERROR, "backend emitted an empty diarization result");
        finish_provider_callback(session);
        return;
    }

    runanywhere::v1::DiarizationResult snapshot;
    const auto* service = static_cast<const rac_diarization_service_t*>(session->service);
    const rac_result_t rc = rac::diarization::result_to_proto(
        *result, service ? service->model_id : nullptr, &snapshot);
    if (rc != RAC_SUCCESS) {
        {
            std::lock_guard<std::mutex> lock(session->mutex);
            session->callback_error = rc;
        }
        dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_ERROR, nullptr, rc,
                       "backend emitted an invalid diarization result");
        finish_provider_callback(session);
        return;
    }

    {
        std::lock_guard<std::mutex> lock(session->mutex);
        session->last_snapshot.CopyFrom(snapshot);
        session->has_snapshot = true;
    }
    // Flush may synchronously refine the complete snapshot more than once.
    // Buffer those refinements and let finalize_session emit exactly one FINAL
    // after the provider call returns; the last valid snapshot wins.
    if (!final) {
        dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_UPDATE, &snapshot);
    }
    finish_provider_callback(session);
}

void maybe_finalize_deferred(const std::shared_ptr<StreamSession>& session) {
    bool finalize = false;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (session->cleanup_deferred && !session->cleanup_claimed &&
            session->termination != Termination::kActive && session->feeds_in_flight == 0 &&
            session->provider_callbacks_in_flight == 0) {
            session->cleanup_claimed = true;
            finalize = true;
        }
    }
    if (finalize) {
        (void)finalize_session(session);
    }
}

void finish_provider_callback(const std::shared_ptr<StreamSession>& session) {
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (session->provider_callbacks_in_flight > 0) {
            --session->provider_callbacks_in_flight;
        }
    }
    session->cv.notify_all();
    maybe_finalize_deferred(session);
}

class FeedGuard {
   public:
    explicit FeedGuard(std::shared_ptr<StreamSession> session) : session_(std::move(session)) {}
    ~FeedGuard() {
        {
            std::lock_guard<std::mutex> lock(session_->mutex);
            if (session_->feeds_in_flight > 0) {
                --session_->feeds_in_flight;
            }
        }
        session_->cv.notify_all();
        maybe_finalize_deferred(session_);
    }

   private:
    std::shared_ptr<StreamSession> session_;
};

rac_result_t finalize_session(const std::shared_ptr<StreamSession>& session) {
    Termination termination = Termination::kCancel;
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        termination = session->termination;
    }

    rac_result_t rc = RAC_SUCCESS;
    if (termination == Termination::kStop) {
        {
            std::lock_guard<std::mutex> lock(session->mutex);
            session->flushing = true;
            session->callback_error = RAC_SUCCESS;
        }
        rc = rac_diarization_stream_feed_audio_chunk(session->service, session->backend_stream,
                                                     nullptr, 0, provider_callback,
                                                     session->callback_context.get());

        runanywhere::v1::DiarizationResult last;
        bool emit_final = false;
        rac_result_t callback_rc = RAC_SUCCESS;
        {
            std::lock_guard<std::mutex> lock(session->mutex);
            callback_rc = session->callback_error;
            emit_final = rc == RAC_SUCCESS && callback_rc == RAC_SUCCESS && !session->final_emitted;
            if (emit_final) {
                session->final_emitted = true;
            }
            if (session->has_snapshot) {
                last.CopyFrom(session->last_snapshot);
            } else {
                const auto* service =
                    static_cast<const rac_diarization_service_t*>(session->service);
                if (service && service->model_id) {
                    last.set_model_id(service->model_id);
                }
            }
        }
        if (rc != RAC_SUCCESS) {
            dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_ERROR, nullptr,
                           rc, rac_error_message(rc));
        } else if (callback_rc != RAC_SUCCESS) {
            rc = callback_rc;
        } else if (emit_final) {
            dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_FINAL, &last);
        }
    }

    {
        std::lock_guard<std::mutex> lock(session->mutex);
        session->drop_events = true;
        session->flushing = false;
    }
    const rac_result_t destroy_rc =
        rac_diarization_stream_destroy(session->service, session->backend_stream);
    if (rc == RAC_SUCCESS && destroy_rc != RAC_SUCCESS) {
        rc = destroy_rc;
    }
    rac_lifecycle_release_service(session->lifecycle);

    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        const auto it = sessions().find(session->id);
        if (it != sessions().end() && it->second == session) {
            sessions().erase(it);
        }
    }
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        session->backend_stream = nullptr;
        session->service = nullptr;
        session->cleanup_finished = true;
    }
    session->cv.notify_all();
    return rc;
}

rac_result_t terminate_session(uint64_t session_id, Termination requested) {
    std::shared_ptr<StreamSession> session;
    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        const auto it = sessions().find(session_id);
        if (it == sessions().end()) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        session = it->second;
    }

    const bool reentrant = g_dispatching_session == session_id;
    {
        std::unique_lock<std::mutex> lock(session->mutex);
        if (session->termination == Termination::kActive || requested == Termination::kCancel) {
            session->termination = requested;
        }
        if (requested == Termination::kCancel || reentrant) {
            session->drop_events = true;
        }
        if (reentrant) {
            if (!session->cleanup_claimed) {
                session->cleanup_deferred = true;
            }
            return RAC_SUCCESS;
        }

        session->cv.wait(lock, [&] {
            return (session->feeds_in_flight == 0 && session->provider_callbacks_in_flight == 0) ||
                   session->cleanup_claimed;
        });
        if (session->cleanup_claimed) {
            session->cv.wait(lock, [&] { return session->cleanup_finished; });
            return RAC_SUCCESS;
        }
        session->cleanup_claimed = true;
    }
    return finalize_session(session);
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

namespace rac::diarization {

void register_stream_component(rac_handle_t component_handle, rac_handle_t lifecycle_handle) {
    if (!component_handle || !lifecycle_handle) {
        return;
    }
    uint64_t owner_id = component_ids().fetch_add(1, std::memory_order_relaxed) + 1;
    if (owner_id == 0) {
        owner_id = component_ids().fetch_add(1, std::memory_order_relaxed) + 1;
    }
    std::lock_guard<std::mutex> lock(registry_mutex());
    stream_components()[component_handle] = StreamComponent{
        .lifecycle = lifecycle_handle, .owner_id = owner_id, .accepting_sessions = true};
}

void unregister_stream_component(rac_handle_t component_handle) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    callback_slots().erase(component_handle);
    stream_components().erase(component_handle);
}

rac_result_t begin_stream_component_teardown(rac_handle_t component_handle) {
    if (!component_handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }
#if defined(RAC_HAVE_PROTOBUF)
    std::vector<uint64_t> owned_sessions;
#endif
    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        auto component = stream_components().find(component_handle);
        if (component == stream_components().end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        if (!component->second.accepting_sessions) {
            return RAC_ERROR_SERVICE_BUSY;
        }
#if defined(RAC_HAVE_PROTOBUF)
        if (g_dispatching_session != 0) {
            const auto dispatching = sessions().find(g_dispatching_session);
            if (dispatching != sessions().end() &&
                dispatching->second->component == component_handle) {
                return RAC_ERROR_SERVICE_BUSY;
            }
        }
#endif
        component->second.accepting_sessions = false;
#if defined(RAC_HAVE_PROTOBUF)
        for (const auto& [id, session] : sessions()) {
            if (session->component == component_handle) {
                owned_sessions.push_back(id);
            }
        }
#endif
    }
#if defined(RAC_HAVE_PROTOBUF)
    for (uint64_t id : owned_sessions) {
        const rac_result_t rc = terminate_session(id, Termination::kCancel);
        if (rc != RAC_SUCCESS && rc != RAC_ERROR_INVALID_ARGUMENT) {
            end_stream_component_teardown(component_handle);
            return rc;
        }
    }
#endif
    return RAC_SUCCESS;
}

void end_stream_component_teardown(rac_handle_t component_handle) {
    std::lock_guard<std::mutex> lock(registry_mutex());
    const auto component = stream_components().find(component_handle);
    if (component != stream_components().end()) {
        component->second.accepting_sessions = true;
    }
}

}  // namespace rac::diarization

extern "C" {

rac_result_t rac_diarization_set_stream_proto_callback(
    rac_handle_t handle, rac_diarization_stream_proto_callback_fn callback, void* user_data) {
    if (!handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> lock(registry_mutex());
    const auto component = stream_components().find(handle);
    if (component == stream_components().end()) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!component->second.accepting_sessions) {
        return RAC_ERROR_SERVICE_BUSY;
    }
    if (!callback) {
        callback_slots().erase(handle);
    } else {
        callback_slots()[handle] = CallbackSlot{callback, user_data};
    }
    return RAC_SUCCESS;
}

rac_result_t rac_diarization_unset_stream_proto_callback(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    std::lock_guard<std::mutex> lock(registry_mutex());
    callback_slots().erase(handle);
    return RAC_SUCCESS;
}

void rac_diarization_proto_quiesce(void) {
    std::unique_lock<std::mutex> lock(callback_tracker_mutex());
    const std::thread::id caller = std::this_thread::get_id();
    // External callers drain a snapshot of every callback admitted so far.
    // Re-entrant callers wait only for earlier admissions on other threads;
    // this strict epoch ordering prevents two callbacks that both quiesce from
    // waiting on one another forever.
    const uint64_t cutoff =
        g_current_callback ? g_current_callback->epoch - 1 : next_callback_epoch() - 1;
    callback_tracker_cv().wait(lock, [&] {
        for (CallbackInvocation* invocation = active_callbacks(); invocation;
             invocation = invocation->active_next) {
            if (invocation->epoch <= cutoff && invocation->owner != caller) {
                return false;
            }
        }
        return true;
    });
}

rac_result_t rac_diarization_stream_start_proto(rac_handle_t handle,
                                                const uint8_t* options_proto_bytes,
                                                size_t options_proto_size,
                                                uint64_t* out_session_id) {
    rac::diarization::ComponentOperationLease component_lease(handle);
    if (!component_lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!out_session_id) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_session_id = 0;
    if (options_proto_size > 0 && !options_proto_bytes) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)options_proto_bytes;
    (void)options_proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    rac_handle_t lifecycle = nullptr;
    uint64_t owner_id = 0;
    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        const auto component = stream_components().find(handle);
        if (component == stream_components().end()) {
            return RAC_ERROR_INVALID_HANDLE;
        }
        if (!component->second.accepting_sessions) {
            return RAC_ERROR_SERVICE_BUSY;
        }
        lifecycle = component_lease.lifecycle();
        owner_id = component->second.owner_id;
    }

    runanywhere::v1::DiarizationOptions parsed;
    if (options_proto_size > 0 &&
        !parsed.ParseFromArray(options_proto_bytes, static_cast<int>(options_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    rac_diarization_options_t options = RAC_DIARIZATION_OPTIONS_DEFAULT;
    runanywhere::v1::DiarizationAudioEncoding encoding =
        runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_F32_LE;
    rac_result_t rc = rac::diarization::options_from_proto(
        options_proto_size > 0 ? &parsed : nullptr, &options, &encoding);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rac_handle_t service = nullptr;
    rc = rac_lifecycle_acquire_service(lifecycle, &service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rac_handle_t backend_stream = nullptr;
    rc = rac_diarization_stream_create(service, &options, &backend_stream);
    if (rc != RAC_SUCCESS) {
        rac_lifecycle_release_service(lifecycle);
        return rc;
    }

    std::shared_ptr<StreamSession> session;
    try {
        session = std::make_shared<StreamSession>();
        session->callback_context = std::make_unique<ProviderCallbackContext>();
    } catch (...) {
        (void)rac_diarization_stream_destroy(service, backend_stream);
        rac_lifecycle_release_service(lifecycle);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    session->id = session_ids().next();
    session->component = handle;
    session->lifecycle = lifecycle;
    session->service = service;
    session->backend_stream = backend_stream;
    session->options = options;
    session->encoding = encoding;
    session->callback_context->session = session;

    rac_result_t publish_rc = RAC_SUCCESS;
    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        const auto component = stream_components().find(handle);
        if (component == stream_components().end() || component->second.owner_id != owner_id ||
            !component->second.accepting_sessions) {
            publish_rc = component == stream_components().end() ? RAC_ERROR_INVALID_HANDLE
                                                                : RAC_ERROR_SERVICE_BUSY;
        } else {
            sessions()[session->id] = session;
        }
    }
    if (publish_rc != RAC_SUCCESS) {
        {
            std::lock_guard<std::mutex> lock(session->mutex);
            session->termination = Termination::kCancel;
            session->drop_events = true;
        }
        (void)rac_diarization_stream_destroy(service, backend_stream);
        rac_lifecycle_release_service(lifecycle);
        return publish_rc;
    }
    *out_session_id = session->id;
    dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_STARTED, nullptr);
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_diarization_stream_feed_audio_proto(uint64_t session_id,
                                                     const uint8_t* audio_bytes,
                                                     size_t audio_size) {
    if (session_id == 0 || (audio_size > 0 && !audio_bytes)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)audio_bytes;
    (void)audio_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    std::shared_ptr<StreamSession> session;
    {
        std::lock_guard<std::mutex> lock(registry_mutex());
        const auto it = sessions().find(session_id);
        if (it == sessions().end()) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        session = it->second;
    }
    if (audio_size == 0) {
        return RAC_SUCCESS;
    }

    std::vector<float> samples;
    rac_result_t rc = rac::diarization::decode_audio(
        audio_bytes, audio_size, session->encoding, session->options.channel_count, true, &samples);
    if (rc != RAC_SUCCESS) {
        dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_ERROR, nullptr, rc,
                       "invalid diarization PCM audio chunk");
        return rc;
    }

    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (session->termination != Termination::kActive) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        if (session->feeds_in_flight != 0) {
            return RAC_ERROR_SERVICE_BUSY;
        }
        ++session->feeds_in_flight;
        session->callback_error = RAC_SUCCESS;
    }
    FeedGuard guard(session);
    rc = rac_diarization_stream_feed_audio_chunk(session->service, session->backend_stream,
                                                 samples.data(), samples.size(), provider_callback,
                                                 session->callback_context.get());
    if (rc != RAC_SUCCESS) {
        dispatch_event(session, runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_ERROR, nullptr, rc,
                       rac_error_message(rc));
        return rc;
    }
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        if (session->callback_error != RAC_SUCCESS) {
            return session->callback_error;
        }
    }
    return RAC_SUCCESS;
#endif
}

rac_result_t rac_diarization_stream_stop_proto(uint64_t session_id) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session_id;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (session_id == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return terminate_session(session_id, Termination::kStop);
#endif
}

rac_result_t rac_diarization_stream_cancel_proto(uint64_t session_id) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)session_id;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (session_id == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return terminate_session(session_id, Termination::kCancel);
#endif
}

}  // extern "C"

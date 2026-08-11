#ifndef RAC_JNI_REQUEST_CANCELLATION_RELAY_H
#define RAC_JNI_REQUEST_CANCELLATION_RELAY_H

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>

namespace rac::jni {

/**
 * Request-id admission state for a synchronous JNI call with an unscoped
 * native cancel function.
 *
 * Kotlin allocates monotonically increasing ids and serializes calls for one
 * native cancel domain. A cancel that wins before JNI entry is retained only
 * for that id; a cancel that sees an active wrapper may safely pulse the
 * underlying idempotent cancel until the wrapper completes. Completion and a
 * cancel pulse are mutually exclusive, so the pulse can never target a
 * successor request.
 */
class RequestCancellationRelay {
   public:
    enum class StartResult { kRun, kCancelled, kInvalid };
    enum class CancelResult { kPending, kActive, kCompleted, kInvalid };

    StartResult start(uint64_t request_id) {
        if (request_id == 0) {
            return StartResult::kInvalid;
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if (request_id <= last_completed_id_ || active_request_id_ != 0) {
            return StartResult::kInvalid;
        }
        if (pending_cancel_id_ == request_id) {
            pending_cancel_id_ = 0;
            last_completed_id_ = std::max(last_completed_id_, request_id);
            completion_cv_.notify_all();
            return StartResult::kCancelled;
        }
        if (pending_cancel_id_ != 0) {
            if (pending_cancel_id_ > request_id) {
                return StartResult::kInvalid;
            }
            // The older Kotlin owner unwound before reaching JNI (for example,
            // payload encoding failed). Monotonic ids plus the Kotlin domain
            // gate guarantee it can no longer enter once its successor does.
            last_completed_id_ = std::max(last_completed_id_, pending_cancel_id_);
            pending_cancel_id_ = 0;
        }
        active_request_id_ = request_id;
        return StartResult::kRun;
    }

    void complete(uint64_t request_id) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (active_request_id_ != request_id) {
            return;
        }
        active_request_id_ = 0;
        last_completed_id_ = std::max(last_completed_id_, request_id);
        completion_cv_.notify_all();
    }

    /**
     * Record cancellation. [dispatch] runs while completion is excluded when
     * this id is active, closing the native-return/stale-cancel race.
     */
    template <typename Dispatch>
    CancelResult request_cancel(uint64_t request_id, Dispatch&& dispatch) {
        if (request_id == 0) {
            return CancelResult::kInvalid;
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if (request_id <= last_completed_id_) {
            return CancelResult::kCompleted;
        }
        if (active_request_id_ == request_id) {
            dispatch();
            return CancelResult::kActive;
        }
        if (active_request_id_ != 0 ||
            (pending_cancel_id_ != 0 && pending_cancel_id_ != request_id)) {
            return CancelResult::kInvalid;
        }
        pending_cancel_id_ = request_id;
        dispatch();
        return CancelResult::kPending;
    }

    /**
     * Pulse an active request's silent cancel while excluding completion.
     * Returns false once this id no longer owns the JNI wrapper.
     */
    template <typename Dispatch>
    bool pulse_if_active(uint64_t request_id, Dispatch&& dispatch) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (active_request_id_ != request_id) {
            return false;
        }
        dispatch();
        return true;
    }

    bool wait_until_retry_or_complete(uint64_t request_id,
                                      std::chrono::milliseconds retry_interval) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (active_request_id_ != request_id) {
            return false;
        }
        completion_cv_.wait_for(lock, retry_interval,
                                [this, request_id] { return active_request_id_ != request_id; });
        return active_request_id_ == request_id;
    }

   private:
    std::mutex mutex_;
    std::condition_variable completion_cv_;
    uint64_t active_request_id_ = 0;
    uint64_t pending_cancel_id_ = 0;
    uint64_t last_completed_id_ = 0;
};

class RequestCompletionGuard {
   public:
    RequestCompletionGuard(RequestCancellationRelay* relay, uint64_t request_id)
        : relay_(relay), request_id_(request_id) {}
    ~RequestCompletionGuard() {
        if (relay_ != nullptr) {
            relay_->complete(request_id_);
        }
    }

    RequestCompletionGuard(const RequestCompletionGuard&) = delete;
    RequestCompletionGuard& operator=(const RequestCompletionGuard&) = delete;

   private:
    RequestCancellationRelay* relay_;
    uint64_t request_id_;
};

}  // namespace rac::jni

#endif  // RAC_JNI_REQUEST_CANCELLATION_RELAY_H

#include "test_common.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/device/rac_device_manager.h"

namespace {

void get_info(rac_device_registration_info_t*, void*) {}
const char* get_id(void*) {
    return "web-test-device";
}
char mutable_device_id[64] = "mutable-device-id";
const char* get_mutable_id(void*) {
    return mutable_device_id;
}
rac_bool_t is_registered(void*) {
    return RAC_FALSE;
}
void set_registered(rac_bool_t, void*) {}
rac_result_t http_post(const char*, const char*, rac_bool_t, rac_device_http_response_t*, void*) {
    return RAC_SUCCESS;
}

struct BlockingCallbackState {
    std::mutex mutex;
    std::condition_variable cv;
    bool callback_entered = false;
    bool release_callback = false;
};

rac_bool_t blocking_is_registered(void* user_data) {
    auto* state = static_cast<BlockingCallbackState*>(user_data);
    std::unique_lock<std::mutex> lock(state->mutex);
    state->callback_entered = true;
    state->cv.notify_all();
    state->cv.wait(lock, [&]() { return state->release_callback; });
    return RAC_FALSE;
}

TestResult test_clear_callbacks_prevents_late_dispatch() {
    rac_device_callbacks_t callbacks = {};
    callbacks.get_device_info = get_info;
    callbacks.get_device_id = get_id;
    callbacks.is_registered = is_registered;
    callbacks.set_registered = set_registered;
    callbacks.http_post = http_post;

    ASSERT_EQ(rac_device_manager_set_callbacks(&callbacks), RAC_SUCCESS,
              "valid callback table must install");
    rac_device_manager_clear_callbacks();
    ASSERT_EQ(rac_device_manager_register_if_needed(RAC_ENV_PRODUCTION, nullptr),
              RAC_ERROR_NOT_INITIALIZED,
              "cleared callbacks must never dispatch through released trampolines");
    ASSERT_TRUE(rac_device_manager_is_registered() == RAC_FALSE,
                "cleared callback state must report unregistered");
    return TEST_PASS();
}

TestResult test_clear_callbacks_waits_for_in_flight_dispatch() {
    BlockingCallbackState state;
    rac_device_callbacks_t callbacks = {};
    callbacks.get_device_info = get_info;
    callbacks.get_device_id = get_id;
    callbacks.is_registered = blocking_is_registered;
    callbacks.set_registered = set_registered;
    callbacks.http_post = http_post;
    callbacks.user_data = &state;

    ASSERT_EQ(rac_device_manager_set_callbacks(&callbacks), RAC_SUCCESS,
              "valid blocking callback table must install");

    std::thread registration(
        [&]() { (void)rac_device_manager_register_if_needed(RAC_ENV_PRODUCTION, nullptr); });
    bool callback_entered = false;
    {
        std::unique_lock<std::mutex> lock(state.mutex);
        callback_entered = state.cv.wait_for(lock, std::chrono::seconds(2),
                                             [&]() { return state.callback_entered; });
    }
    if (!callback_entered) {
        {
            std::lock_guard<std::mutex> lock(state.mutex);
            state.release_callback = true;
        }
        state.cv.notify_all();
        registration.join();
        rac_device_manager_clear_callbacks();
        ASSERT_TRUE(false, "registration must enter the blocking callback");
    }

    std::atomic<bool> clear_started{false};
    std::atomic<bool> clear_returned{false};
    std::thread clear_thread([&]() {
        clear_started.store(true, std::memory_order_release);
        rac_device_manager_clear_callbacks();
        clear_returned.store(true, std::memory_order_release);
    });
    while (!clear_started.load(std::memory_order_acquire)) {
        std::this_thread::yield();
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
    const bool clear_returned_while_in_flight = clear_returned.load(std::memory_order_acquire);

    {
        std::lock_guard<std::mutex> lock(state.mutex);
        state.release_callback = true;
    }
    state.cv.notify_all();
    registration.join();
    clear_thread.join();

    ASSERT_TRUE(!clear_returned_while_in_flight,
                "clear must wait while a callback dispatch is in flight");
    ASSERT_TRUE(clear_returned.load(std::memory_order_acquire),
                "clear must finish after the in-flight callback returns");
    ASSERT_EQ(rac_device_manager_register_if_needed(RAC_ENV_PRODUCTION, nullptr),
              RAC_ERROR_NOT_INITIALIZED,
              "quiescent clear must prevent subsequent callback dispatch");
    return TEST_PASS();
}

TestResult test_get_device_id_survives_concurrent_callback_release() {
    std::strcpy(mutable_device_id, "mutable-device-id");

    rac_device_callbacks_t callbacks = {};
    callbacks.get_device_info = get_info;
    callbacks.get_device_id = get_mutable_id;
    callbacks.is_registered = is_registered;
    callbacks.set_registered = set_registered;
    callbacks.http_post = http_post;
    ASSERT_EQ(rac_device_manager_set_callbacks(&callbacks), RAC_SUCCESS,
              "mutable callback table must install");

    std::mutex barrier_mutex;
    std::condition_variable barrier;
    bool getter_returned = false;
    bool callback_storage_released = false;
    std::string observed;

    std::thread reader([&]() {
        const char* device_id = rac_device_manager_get_device_id();
        {
            std::lock_guard<std::mutex> lock(barrier_mutex);
            getter_returned = true;
        }
        barrier.notify_one();

        {
            std::unique_lock<std::mutex> lock(barrier_mutex);
            barrier.wait(lock, [&]() { return callback_storage_released; });
        }
        observed = device_id ? device_id : "";
    });

    {
        std::unique_lock<std::mutex> lock(barrier_mutex);
        barrier.wait(lock, [&]() { return getter_returned; });
    }
    rac_device_manager_clear_callbacks();
    std::strcpy(mutable_device_id, "released");
    {
        std::lock_guard<std::mutex> lock(barrier_mutex);
        callback_storage_released = true;
    }
    barrier.notify_one();
    reader.join();

    ASSERT_TRUE(observed == "mutable-device-id",
                "returned device id must not borrow callback-owned storage");
    ASSERT_TRUE(rac_device_manager_get_device_id() == nullptr,
                "cleared callbacks must not expose a stale snapshot");
    return TEST_PASS();
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("device_manager_callbacks");
    suite.add("clear_callbacks_prevents_late_dispatch",
              test_clear_callbacks_prevents_late_dispatch);
    suite.add("clear_callbacks_waits_for_in_flight_dispatch",
              test_clear_callbacks_waits_for_in_flight_dispatch);
    suite.add("get_device_id_survives_concurrent_callback_release",
              test_get_device_id_survives_concurrent_callback_release);
    return suite.run(argc, argv);
}

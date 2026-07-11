#include "test_common.h"

#include "rac/core/rac_error.h"
#include "rac/infrastructure/device/rac_device_manager.h"

namespace {

void get_info(rac_device_registration_info_t*, void*) {}
const char* get_id(void*) { return "web-test-device"; }
rac_bool_t is_registered(void*) { return RAC_FALSE; }
void set_registered(rac_bool_t, void*) {}
rac_result_t http_post(const char*, const char*, rac_bool_t,
                       rac_device_http_response_t*, void*) {
    return RAC_SUCCESS;
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

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("device_manager_callbacks");
    suite.add("clear_callbacks_prevents_late_dispatch",
              test_clear_callbacks_prevents_late_dispatch);
    return suite.run(argc, argv);
}

/**
 * @file test_connect_transport_registry.cpp
 * @brief Registry lifecycle tests for Connect transport registration.
 */

#include <atomic>
#include <cstdio>

#include "rac/connect/rac_connect_transport.h"

namespace {

int g_checks = 0;
int g_failures = 0;

#define CHECK(condition, label)                                                      \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (condition) {                                                             \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                            \
    } while (0)

std::atomic<int> g_destroy_calls{0};

rac_result_t failing_init(void* /*user_data*/) {
    return RAC_ERROR_PROCESSING_FAILED;
}

void counting_destroy(void* /*user_data*/) {
    g_destroy_calls.fetch_add(1);
}

rac_result_t unused_open(void* /*user_data*/, const rac_connect_endpoint_t* /*endpoint*/,
                         rac_connect_channel_t* /*out_channel*/) {
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_result_t unused_send(void* /*user_data*/, rac_connect_channel_t /*channel*/,
                         const uint8_t* /*payload*/, size_t /*payload_size*/) {
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_result_t unused_receive(void* /*user_data*/, rac_connect_channel_t /*channel*/,
                            rac_proto_buffer_t* /*out_payload*/) {
    return RAC_ERROR_NOT_IMPLEMENTED;
}

rac_result_t unused_close(void* /*user_data*/, rac_connect_channel_t /*channel*/) {
    return RAC_ERROR_NOT_IMPLEMENTED;
}

void test_failed_init_does_not_destroy() {
    g_destroy_calls.store(0);
    rac_connect_transport_ops_t ops{};
    ops.abi_version = RAC_CONNECT_TRANSPORT_ABI_VERSION;
    ops.struct_size = sizeof(ops);
    ops.open = unused_open;
    ops.send = unused_send;
    ops.receive = unused_receive;
    ops.close = unused_close;
    ops.init = failing_init;
    ops.destroy = counting_destroy;

    const rac_result_t result = rac_connect_transport_register(&ops, nullptr);
    CHECK(result == RAC_ERROR_PROCESSING_FAILED, "Failed init propagates to the caller");
    CHECK(g_destroy_calls.load() == 0, "Failed init must not invoke destroy");
    CHECK(rac_connect_transport_is_registered() == RAC_FALSE,
          "Failed init leaves the registry empty");
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_connect_transport_registry\n");
    test_failed_init_does_not_destroy();
    (void)rac_connect_transport_register(nullptr, nullptr);
    std::fprintf(stdout, "  %d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}

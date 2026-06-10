/**
 * @file test_log_redact.cpp
 * @brief Parity tests for `rac_log_metadata_should_redact()`.
 *
 * Validates the centralized C++ redaction policy against the same fixture set
 * Swift's `SDKLogger` honors. Keys containing any of "key", "secret",
 * "password", "token", "auth", or "credential" (case-insensitive substring
 * match) must be redacted; everything else must pass through.
 */

#include "test_common.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"

namespace {

TestResult run_positive_cases() {
    struct Case {
        const char* key;
        const char* note;
    };
    constexpr Case cases[] = {
        {"api_key", "lowercase 'key' substring"},
        {"Authorization", "case-insensitive 'auth'"},
        {"X-Auth-Token", "two patterns ('auth' + 'token')"},
        {"userPassword", "camelCase 'password'"},
        {"credentials", "plural 'credential'"},
        {"secretSauce", "leading 'secret'"},
        {"Token", "uppercase first letter"},
        {"TOKEN", "all-uppercase"},
    };

    for (const Case& c : cases) {
        rac_bool_t out = RAC_FALSE;
        const rac_result_t rc = rac_log_metadata_should_redact(c.key, &out);
        ASSERT_EQ(rc, RAC_SUCCESS, std::string("expected SUCCESS for ") + c.key);
        if (out != RAC_TRUE) {
            TestResult fail;
            fail.passed = false;
            fail.expected = "RAC_TRUE (redacted)";
            fail.actual = "RAC_FALSE";
            fail.details =
                std::string("positive case '") + c.key + "' (" + c.note + ") was NOT redacted";
            return fail;
        }
    }
    return TEST_PASS();
}

TestResult run_negative_cases() {
    constexpr const char* keys[] = {
        "user_id",
        "request_id",
        "model_name",
        "url",
    };

    for (const char* key : keys) {
        rac_bool_t out = RAC_TRUE;
        const rac_result_t rc = rac_log_metadata_should_redact(key, &out);
        ASSERT_EQ(rc, RAC_SUCCESS, std::string("expected SUCCESS for ") + key);
        if (out != RAC_FALSE) {
            TestResult fail;
            fail.passed = false;
            fail.expected = "RAC_FALSE (not redacted)";
            fail.actual = "RAC_TRUE";
            fail.details = std::string("benign key '") + key + "' was incorrectly redacted";
            return fail;
        }
    }
    return TEST_PASS();
}

TestResult run_null_key_rejected() {
    rac_bool_t out = RAC_FALSE;
    const rac_result_t rc = rac_log_metadata_should_redact(nullptr, &out);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER, "NULL key must return RAC_ERROR_NULL_POINTER");
    return TEST_PASS();
}

TestResult run_null_out_rejected() {
    const rac_result_t rc = rac_log_metadata_should_redact("api_key", nullptr);
    ASSERT_EQ(rc, RAC_ERROR_NULL_POINTER, "NULL out must return RAC_ERROR_NULL_POINTER");
    return TEST_PASS();
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("log_redact");
    suite.add("positive_cases", run_positive_cases);
    suite.add("negative_cases", run_negative_cases);
    suite.add("null_key_rejected", run_null_key_rejected);
    suite.add("null_out_rejected", run_null_out_rejected);
    return suite.run(argc, argv);
}

/**
 * @file test_bundle_policy.cpp
 * @brief Tests for the per-framework bundle-policy registry, plus offline
 *        coverage of the QHexRT policy (the first registrant).
 *
 * The registry itself is pure mechanism (register/find/replace/unregister +
 * ABI guard). The QHexRT policy lives header-only in engines/qhexrt/
 * (public-repo source, no prebuilt needed), so this commons test can include
 * it directly and exercise the real predicate end-to-end through the generic
 * folder resolver. No network, no engine binaries.
 */

#include "test_common.h"

#include <string>
#include <vector>

#include "rac/infrastructure/model_management/rac_bundle_policy.h"

#include "../src/infrastructure/model_management/hf_resolver.h"
#include "qhexrt_bundle_policy.h"

namespace hf = rac::infra::model_management::hf;

namespace {

TestResult expect(const std::string& name, bool condition, const std::string& details = "") {
    TestResult r;
    r.test_name = name;
    r.passed = condition;
    r.details = details;
    return r;
}

rac_bool_t always_true(const char* /*relative_path*/) { return RAC_TRUE; }

void test_registry(std::vector<TestResult>& results) {
    // Invalid registrations.
    results.push_back(expect("register NULL rejected",
                             rac_bundle_policy_register(nullptr) == RAC_ERROR_INVALID_ARGUMENT));
    rac_bundle_policy_t bad{};
    bad.struct_size = sizeof(rac_bundle_policy_t);
    bad.framework = RAC_FRAMEWORK_UNKNOWN;
    results.push_back(expect("register UNKNOWN framework rejected",
                             rac_bundle_policy_register(&bad) == RAC_ERROR_INVALID_ARGUMENT));
    static rac_bundle_policy_t wrong_size{};
    wrong_size.struct_size = 12;
    wrong_size.framework = RAC_FRAMEWORK_SHERPA;
    results.push_back(expect("register wrong struct_size rejected",
                             rac_bundle_policy_register(&wrong_size) ==
                                 RAC_ERROR_ABI_VERSION_MISMATCH));

    // Register / find / replace / unregister.
    static rac_bundle_policy_t policy_a{};
    policy_a.struct_size = sizeof(rac_bundle_policy_t);
    policy_a.framework = RAC_FRAMEWORK_SHERPA;
    policy_a.manifest_extension = ".json";
    static rac_bundle_policy_t policy_b = policy_a;
    policy_b.is_bundle_manifest = always_true;

    results.push_back(expect("find before register is NULL",
                             rac_bundle_policy_find(RAC_FRAMEWORK_SHERPA) == nullptr));
    results.push_back(
        expect("register ok", rac_bundle_policy_register(&policy_a) == RAC_SUCCESS));
    results.push_back(expect("find returns registrant",
                             rac_bundle_policy_find(RAC_FRAMEWORK_SHERPA) == &policy_a));
    results.push_back(
        expect("re-register replaces", rac_bundle_policy_register(&policy_b) == RAC_SUCCESS &&
                                           rac_bundle_policy_find(RAC_FRAMEWORK_SHERPA) ==
                                               &policy_b));
    results.push_back(expect("unregister removes",
                             rac_bundle_policy_unregister(RAC_FRAMEWORK_SHERPA) == RAC_SUCCESS &&
                                 rac_bundle_policy_find(RAC_FRAMEWORK_SHERPA) == nullptr));
    results.push_back(expect("unregister absent is ok",
                             rac_bundle_policy_unregister(RAC_FRAMEWORK_SHERPA) == RAC_SUCCESS));
}

void test_qhexrt_predicate(std::vector<TestResult>& results) {
    results.push_back(expect("qhexrt: manifest json accepted",
                             qhexrt_is_bundle_manifest("whisper-small.json") == RAC_TRUE));
    results.push_back(expect("qhexrt: case-insensitive extension",
                             qhexrt_is_bundle_manifest("Model.JSON") == RAC_TRUE));
    results.push_back(expect("qhexrt: tokenizer.json rejected",
                             qhexrt_is_bundle_manifest("tokenizer.json") == RAC_FALSE));
    results.push_back(expect("qhexrt: config.json rejected",
                             qhexrt_is_bundle_manifest("config.json") == RAC_FALSE));
    results.push_back(expect("qhexrt: nested json rejected",
                             qhexrt_is_bundle_manifest("host_weights/x.json") == RAC_FALSE));
    results.push_back(
        expect("qhexrt: binary rejected", qhexrt_is_bundle_manifest("dec.bin") == RAC_FALSE));
    results.push_back(expect("qhexrt: NULL rejected",
                             qhexrt_is_bundle_manifest(nullptr) == RAC_FALSE));
}

void test_qhexrt_policy_shape(std::vector<TestResult>& results) {
    const rac_bundle_policy_t* policy = qhexrt_bundle_policy();
    results.push_back(expect("qhexrt policy: framework",
                             policy != nullptr && policy->framework == RAC_FRAMEWORK_QHEXRT));
    results.push_back(expect("qhexrt policy: format QNN_CONTEXT",
                             policy->model_format == RAC_MODEL_FORMAT_QNN_CONTEXT));
    results.push_back(expect("qhexrt policy: manifest-leaf refs enabled",
                             policy->manifest_leaf_names_bundle == RAC_TRUE &&
                                 std::string(policy->manifest_extension) == ".json"));
    results.push_back(expect("qhexrt policy: device variant resolver installed",
                             policy->resolve_variant != nullptr));
    results.push_back(expect("qhexrt policy: registers cleanly",
                             rac_bundle_policy_register(policy) == RAC_SUCCESS &&
                                 rac_bundle_policy_find(RAC_FRAMEWORK_QHEXRT) == policy));
    rac_bundle_policy_unregister(RAC_FRAMEWORK_QHEXRT);
}

// The real QHexRT predicate driven through the generic resolver: an
// HNPU-style tree resolves with the manifest primary and aux sidecars as
// companions.
void test_qhexrt_end_to_end(std::vector<TestResult>& results) {
    const char* tree = R"JSON([
      {"type":"file","path":"config.json","size":42},
      {"type":"file","path":"v81/melotts-en.json","size":900},
      {"type":"file","path":"v81/tokenizer.json","size":10},
      {"type":"file","path":"v81/melo_decoder.bin","size":5000},
      {"type":"file","path":"v81/host_weights/w.bin","size":100}
    ])JSON";
    hf::ResolvedModel resolved;
    std::string error;
    const rac_result_t rc = hf::resolve_folder_from_tree_json(
        tree, "runanywhere", "melotts_en_HNPU", "v81", "", qhexrt_is_bundle_manifest, &resolved,
        &error);
    results.push_back(expect("qhexrt e2e resolves", rc == RAC_SUCCESS, error));
    results.push_back(expect("qhexrt e2e manifest primary",
                             !resolved.files.empty() &&
                                 resolved.files[0].filename == "melotts-en.json"));
    results.push_back(expect("qhexrt e2e file count", resolved.files.size() == 5,
                             "got " + std::to_string(resolved.files.size())));
}

}  // namespace

int main() {
    std::vector<TestResult> results;
    test_registry(results);
    test_qhexrt_predicate(results);
    test_qhexrt_policy_shape(results);
    test_qhexrt_end_to_end(results);
    for (const TestResult& r : results) {
        print_result(r);
    }
    return print_summary(results);
}

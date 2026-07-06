/**
 * @file test_hf_resolver_folder.cpp
 * @brief Offline tests for the generic Hugging Face folder-bundle resolver.
 *
 * Exercises is_folder_ref() and resolve_folder_from_tree_json() — the pure
 * core behind resolve_repo_folder() — against synthetic tree-API responses.
 * The manifest heuristic is injected as a predicate (in production it comes
 * from an engine's registered rac_bundle_policy_t; commons itself carries no
 * framework-specific policy). No network, no platform adapter.
 */

#include "test_common.h"

#include <cstring>
#include <string>
#include <vector>

#include "../src/infrastructure/model_management/hf_resolver.h"

namespace hf = rac::infra::model_management::hf;

namespace {

TestResult expect(const std::string& name, bool condition, const std::string& details = "") {
    TestResult r;
    r.test_name = name;
    r.passed = condition;
    r.details = details;
    return r;
}

// The test fixture's own manifest heuristic: a top-level .json that is not a
// well-known sidecar. (Mirrors what a real engine policy registers.)
rac_bool_t test_is_manifest(const char* relative_path) {
    if (relative_path == nullptr || std::strchr(relative_path, '/') != nullptr) {
        return RAC_FALSE;
    }
    const std::string name(relative_path);
    if (name.size() < 6 || name.substr(name.size() - 5) != ".json") {
        return RAC_FALSE;
    }
    if (name == "tokenizer.json" || name == "config.json") {
        return RAC_FALSE;
    }
    return RAC_TRUE;
}

// A synthetic bundle-style repo tree: root config/README, a v79 bundle with
// one manifest + aux jsons + nested host weights, and a v81 bundle with THREE
// manifests (context-length variants).
const char* kTree = R"JSON([
  {"type":"file","path":".gitattributes","size":100},
  {"type":"file","path":"README.md","size":200},
  {"type":"file","path":"config.json","size":42},
  {"type":"file","path":"v79/whisper-small.json","size":1000},
  {"type":"file","path":"v79/tokenizer.json","size":2000},
  {"type":"file","path":"v79/encoder.bin","size":3000,
   "lfs":{"oid":"abc123","size":3000}},
  {"type":"file","path":"v79/host_weights/w1.bin","size":400},
  {"type":"file","path":"v79/notes.md","size":10},
  {"type":"file","path":"v81/lfm-2048.json","size":900},
  {"type":"file","path":"v81/lfm-4k.json","size":901},
  {"type":"file","path":"v81/lfm-512s.json","size":902},
  {"type":"file","path":"v81/dec.bin","size":5000},
  {"type":"directory","path":"v81/host_weights"}
])JSON";

void test_is_folder_ref(std::vector<TestResult>& results) {
    results.push_back(expect("folder ref: subdir without extension",
                             hf::is_folder_ref("hf.co/org/repo/v81", nullptr)));
    results.push_back(expect("folder ref: trailing slash",
                             hf::is_folder_ref("hf.co/org/repo/v81/", nullptr)));
    results.push_back(expect("folder ref: manifest leaf only with policy extension",
                             !hf::is_folder_ref("hf.co/org/repo/v79/m.json", nullptr) &&
                                 hf::is_folder_ref("hf.co/org/repo/v79/m.json", ".json")));
    results.push_back(expect("not folder ref: repo-level ref",
                             !hf::is_folder_ref("hf.co/org/repo", ".json")));
    results.push_back(expect("not folder ref: explicit file with extension",
                             !hf::is_folder_ref("hf.co/org/repo/path/file.gguf", nullptr)));
    results.push_back(expect(
        "not folder ref: /resolve/ URL",
        !hf::is_folder_ref("https://huggingface.co/org/repo/resolve/main/v81", ".json")));
}

void test_arch_folder_ref(std::vector<TestResult>& results) {
    std::string out;
    results.push_back(expect("logical arch ref: parent repo",
                             hf::is_logical_arch_folder_ref("hf.co/org/repo", ".json")));
    results.push_back(expect("logical arch ref: root manifest",
                             hf::is_logical_arch_folder_ref("hf.co/org/repo/lfm.json", ".json")));
    results.push_back(expect("logical arch ref: query manifest",
                             hf::is_logical_arch_folder_ref("hf.co/org/repo?manifest=vlm.json",
                                                            ".json")));
    results.push_back(expect(
        "logical arch ref: arch-pinned ref stays normal folder",
        !hf::is_logical_arch_folder_ref("hf.co/org/repo/v81/lfm.json", ".json")));
    results.push_back(expect(
        "logical arch ref: resolve URL stays explicit file",
        !hf::is_logical_arch_folder_ref(
            "https://huggingface.co/org/repo/resolve/main/v81/lfm.json", ".json")));
    results.push_back(expect(
        "logical arch ref: conflicting manifest names rejected",
        !hf::is_logical_arch_folder_ref("hf.co/org/repo/foo.json?manifest=bar.json",
                                        ".json")));
    results.push_back(expect(
        "arch ref: parent repo",
        hf::make_arch_folder_ref("hf.co/org/repo", "v81", ".json", &out) &&
            out == "https://huggingface.co/org/repo/v81",
        out));
    results.push_back(expect(
        "arch ref: root manifest leaf",
        hf::make_arch_folder_ref("https://huggingface.co/org/repo/lfm.json", "v81", ".json",
                                 &out) &&
            out == "https://huggingface.co/org/repo/v81/lfm.json",
        out));
    results.push_back(expect(
        "arch ref: query manifest",
        hf::make_arch_folder_ref("hf.co/org/repo?manifest=vlm.json", "v79", ".json", &out) &&
            out == "https://huggingface.co/org/repo/v79/vlm.json",
        out));
    results.push_back(expect("arch ref: parent repo without manifest extension",
                             hf::make_arch_folder_ref("hf.co/org/repo", "v81", nullptr, &out) &&
                                 out == "https://huggingface.co/org/repo/v81",
                             out));
    results.push_back(expect(
        "arch ref: manifest leaf requires extension policy",
        !hf::make_arch_folder_ref("hf.co/org/repo/lfm.json", "v81", nullptr, &out)));
    results.push_back(expect(
        "arch ref: nested manifest path rejected",
        !hf::make_arch_folder_ref("hf.co/org/repo/manifests/lfm.json", "v81", ".json", &out)));
    results.push_back(expect(
        "arch ref: nested query manifest rejected",
        !hf::make_arch_folder_ref("hf.co/org/repo?manifest=manifests/lfm.json", "v81",
                                  ".json", &out)));
    results.push_back(expect(
        "arch ref: old explicit arch stays untouched",
        !hf::make_arch_folder_ref("hf.co/org/repo/v81/lfm.json", "v79", ".json", &out)));
    results.push_back(expect(
        "arch ref: resolve URL untouched",
        !hf::make_arch_folder_ref("https://huggingface.co/org/repo/resolve/main/v81/lfm.json",
                                  "v79", ".json", &out)));
    results.push_back(expect(
        "arch ref: conflicting manifest names rejected",
        !hf::make_arch_folder_ref("hf.co/org/repo/foo.json?manifest=bar.json", "v81",
                                  ".json", &out)));
    results.push_back(expect(
        "arch ref: unknown arch rejected",
        !hf::make_arch_folder_ref("hf.co/org/repo/lfm.json", "unknown", ".json", &out)));
}

void test_subdir_resolution(std::vector<TestResult>& results) {
    hf::ResolvedModel resolved;
    std::string error;
    const rac_result_t rc = hf::resolve_folder_from_tree_json(
        kTree, "org", "repo", "v79", "", test_is_manifest, &resolved, &error);
    results.push_back(expect("v79 resolves", rc == RAC_SUCCESS, error));
    if (rc != RAC_SUCCESS) {
        return;
    }
    // whisper-small.json (manifest, primary) + tokenizer.json + encoder.bin +
    // host_weights/w1.bin + root config.json; notes.md excluded.
    results.push_back(expect("v79 file count", resolved.files.size() == 5,
                             "got " + std::to_string(resolved.files.size())));
    results.push_back(expect("v79 primary is the manifest, ordered first",
                             !resolved.files.empty() &&
                                 resolved.files[0].filename == "whisper-small.json"));
    bool nested_ok = false;
    bool config_last = !resolved.files.empty() && resolved.files.back().filename == "config.json";
    bool md_excluded = true;
    for (const hf::ResolvedFile& f : resolved.files) {
        if (f.filename == "host_weights/w1.bin") {
            nested_ok = f.url.find("/resolve/main/v79/host_weights/w1.bin") != std::string::npos;
        }
        if (f.filename.find(".md") != std::string::npos) {
            md_excluded = false;
        }
    }
    results.push_back(expect("v79 nested path kept relative + full URL", nested_ok));
    results.push_back(expect("v79 root config.json appended last", config_last));
    results.push_back(expect("v79 markdown excluded", md_excluded));
    results.push_back(
        expect("v79 sizes summed", resolved.total_size_bytes == 1000 + 2000 + 3000 + 400 + 42,
               "got " + std::to_string(resolved.total_size_bytes)));
    bool sha_ok = false;
    for (const hf::ResolvedFile& f : resolved.files) {
        if (f.filename == "encoder.bin") {
            sha_ok = f.sha256 == "abc123";
        }
    }
    results.push_back(expect("v79 lfs sha carried", sha_ok));
    results.push_back(expect("v79 derived id", resolved.model_id == "repo-v79"));
}

void test_multi_manifest(std::vector<TestResult>& results) {
    // No explicit manifest: deterministic alphabetical pick (lfm-2048.json).
    hf::ResolvedModel by_default;
    std::string error;
    rac_result_t rc = hf::resolve_folder_from_tree_json(kTree, "org", "repo", "v81", "",
                                                        test_is_manifest, &by_default, &error);
    results.push_back(expect("v81 default manifest resolves", rc == RAC_SUCCESS, error));
    results.push_back(expect("v81 default manifest is alphabetical first",
                             !by_default.files.empty() &&
                                 by_default.files[0].filename == "lfm-2048.json"));

    // Explicit manifest ref pins the primary.
    hf::ResolvedModel pinned;
    rc = hf::resolve_folder_from_tree_json(kTree, "org", "repo", "v81", "lfm-4k.json",
                                           test_is_manifest, &pinned, &error);
    results.push_back(expect("v81 explicit manifest resolves", rc == RAC_SUCCESS, error));
    results.push_back(expect("v81 explicit manifest is primary",
                             !pinned.files.empty() && pinned.files[0].filename == "lfm-4k.json"));

    // Unknown manifest errors out.
    hf::ResolvedModel missing;
    rc = hf::resolve_folder_from_tree_json(kTree, "org", "repo", "v81", "nope.json",
                                           test_is_manifest, &missing, &error);
    results.push_back(expect("v81 unknown manifest fails", rc == RAC_ERROR_NOT_FOUND, error));
}

void test_no_policy(std::vector<TestResult>& results) {
    // No predicate + no explicit primary: cannot choose — actionable error.
    hf::ResolvedModel resolved;
    std::string error;
    rac_result_t rc = hf::resolve_folder_from_tree_json(kTree, "org", "repo", "v79", "", nullptr,
                                                        &resolved, &error);
    results.push_back(expect("no policy + no pin fails with actionable message",
                             rc == RAC_ERROR_NOT_FOUND &&
                                 error.find("register the engine backend") != std::string::npos,
                             error));

    // Explicit pin works WITHOUT any policy — pinning is generic.
    rc = hf::resolve_folder_from_tree_json(kTree, "org", "repo", "v79", "whisper-small.json",
                                           nullptr, &resolved, &error);
    results.push_back(expect("pinned primary works without policy",
                             rc == RAC_SUCCESS && !resolved.files.empty() &&
                                 resolved.files[0].filename == "whisper-small.json",
                             error));
}

void test_errors(std::vector<TestResult>& results) {
    hf::ResolvedModel resolved;
    std::string error;
    rac_result_t rc = hf::resolve_folder_from_tree_json(kTree, "org", "repo", "v83", "",
                                                        test_is_manifest, &resolved, &error);
    results.push_back(expect("missing subdir fails", rc == RAC_ERROR_NOT_FOUND, error));

    rc = hf::resolve_folder_from_tree_json("not json", "org", "repo", "v79", "", test_is_manifest,
                                           &resolved, &error);
    results.push_back(expect("garbage tree body fails", rc == RAC_ERROR_DECODING_ERROR, error));

    // A folder whose only jsons the predicate rejects (aux sidecars).
    const char* no_manifest = R"JSON([
      {"type":"file","path":"v79/enc.bin","size":10},
      {"type":"file","path":"v79/tokenizer.json","size":10}
    ])JSON";
    rc = hf::resolve_folder_from_tree_json(no_manifest, "org", "repo", "v79", "",
                                           test_is_manifest, &resolved, &error);
    results.push_back(expect("aux-only jsons: no manifest fails with hint",
                             rc == RAC_ERROR_NOT_FOUND &&
                                 error.find("name the manifest explicitly") != std::string::npos,
                             error));
}

}  // namespace

int main() {
    std::vector<TestResult> results;
    test_is_folder_ref(results);
    test_arch_folder_ref(results);
    test_subdir_resolution(results);
    test_multi_manifest(results);
    test_no_policy(results);
    test_errors(results);
    for (const TestResult& r : results) {
        print_result(r);
    }
    return print_summary(results);
}

/**
 * @file test_rcli_unit.cpp
 * @brief rcli unit tests — pure helpers, no models, no network.
 *
 * Uses the commons TestSuite harness so the Docker rig and ctest drive every
 * suite the same way (--run-all / --test-<name>).
 */

#include "test_common.h"

#include <cstdlib>
#include <string>

#include "catalog/catalog.h"
#include "catalog/model_ref.h"
#include "config/cli_paths.h"
#include "io/output.h"

namespace {

// setenv/unsetenv helper that restores prior state on scope exit.
class EnvVar {
   public:
    EnvVar(const char* name, const char* value) : name_(name) {
        if (const char* prev = std::getenv(name)) {
            had_prev_ = true;
            prev_ = prev;
        }
        if (value) {
            setenv(name, value, 1);
        } else {
            unsetenv(name);
        }
    }
    ~EnvVar() {
        if (had_prev_) {
            setenv(name_.c_str(), prev_.c_str(), 1);
        } else {
            unsetenv(name_.c_str());
        }
    }

   private:
    std::string name_;
    std::string prev_;
    bool had_prev_ = false;
};

TestResult test_json_escape() {
    TestResult result;
    result.test_name = "json_escape";

    struct Case {
        std::string in;
        std::string expected;
    };
    const Case cases[] = {
        {"plain", "plain"},
        {"quote\"backslash\\", "quote\\\"backslash\\\\"},
        {"line\nbreak\ttab", "line\\nbreak\\ttab"},
        {std::string("ctl\x01", 4), "ctl\\u0001"},
    };
    for (const Case& c : cases) {
        const std::string actual = rcli::out::json_escape(c.in);
        if (actual != c.expected) {
            result.expected = c.expected;
            result.actual = actual;
            return result;
        }
    }
    result.passed = true;
    return result;
}

TestResult test_json_writer_shape() {
    TestResult result;
    result.test_name = "json_writer_shape";

    rcli::out::JsonWriter json;
    json.begin_object()
        .field("name", "qwen3-0.6b")
        .field("size", static_cast<int64_t>(640))
        .field("downloaded", true);
    json.begin_array("files");
    json.begin_array_object().field("path", "a.gguf").end_object();
    json.begin_array_object().field("path", "b.gguf").end_object();
    json.end_array().end_object();

    const std::string expected =
        R"({"name":"qwen3-0.6b","size":640,"downloaded":true,)"
        R"("files":[{"path":"a.gguf"},{"path":"b.gguf"}]})";
    if (json.str() != expected) {
        result.expected = expected;
        result.actual = json.str();
        return result;
    }
    result.passed = true;
    return result;
}

TestResult test_human_bytes() {
    TestResult result;
    result.test_name = "human_bytes";

    struct Case {
        uint64_t in;
        std::string expected;
    };
    const Case cases[] = {
        {512, "512 B"},
        {2048, "2.0 KB"},
        {640ull * 1024 * 1024, "640.0 MB"},
        {3ull * 1024 * 1024 * 1024, "3.0 GB"},
    };
    for (const Case& c : cases) {
        const std::string actual = rcli::out::human_bytes(c.in);
        if (actual != c.expected) {
            result.expected = c.expected;
            result.actual = actual;
            return result;
        }
    }
    result.passed = true;
    return result;
}

TestResult test_normalize_dir() {
    TestResult result;
    result.test_name = "normalize_dir";

    if (rcli::paths::normalize_dir("/a/b/") != "/a/b" ||
        rcli::paths::normalize_dir("/a/b///") != "/a/b" ||
        rcli::paths::normalize_dir("/") != "/" || !rcli::paths::normalize_dir("").empty()) {
        result.details = "trailing-slash handling broken";
        return result;
    }
    result.passed = true;
    return result;
}

TestResult test_resolve_home_precedence() {
    TestResult result;
    result.test_name = "resolve_home_precedence";

    {
        // Flag override wins over env.
        EnvVar env("RUNANYWHERE_HOME", "/from-env/runanywhere");
        if (rcli::paths::resolve_home("/from-flag/runanywhere/") != "/from-flag/runanywhere") {
            result.details = "flag override should win and be normalized";
            return result;
        }
        if (rcli::paths::resolve_home("") != "/from-env/runanywhere") {
            result.details = "env should win when no flag given";
            return result;
        }
    }
    {
        // Default: XDG data dir under runanywhere.
        EnvVar env("RUNANYWHERE_HOME", nullptr);
        EnvVar xdg("XDG_DATA_HOME", "/xdg-data");
        const std::string home = rcli::paths::resolve_home("");
        if (home != "/xdg-data/runanywhere") {
            result.details = "expected /xdg-data/runanywhere, got " + home;
            return result;
        }
    }
    result.passed = true;
    return result;
}

TestResult test_state_dir() {
    TestResult result;
    result.test_name = "state_dir";

    EnvVar xdg("XDG_STATE_HOME", "/xdg-state");
    if (rcli::paths::state_dir() != "/xdg-state/runanywhere") {
        result.details = "XDG_STATE_HOME not honored";
        return result;
    }
    result.passed = true;
    return result;
}

TestResult test_catalog_lookup() {
    TestResult result;
    result.test_name = "catalog_lookup";

    size_t count = 0;
    const rcli::catalog::CatalogEntry* entries = rcli::catalog::all(&count);
    if (!entries || count < 10) {
        result.details = "catalog unexpectedly small";
        return result;
    }

    const rcli::catalog::CatalogEntry* by_id = rcli::catalog::find("qwen3-0.6b");
    const rcli::catalog::CatalogEntry* by_alias = rcli::catalog::find("qwen3");
    if (!by_id || by_id != by_alias) {
        result.details = "alias lookup should resolve to the same entry";
        return result;
    }
    if (rcli::catalog::find("definitely-not-a-model") != nullptr) {
        result.details = "unknown id should return nullptr";
        return result;
    }
    if (rcli::catalog::suggestions("qwen", 3).empty()) {
        result.details = "expected suggestions for 'qwen'";
        return result;
    }

    // Multi-file entries (VLM pairs, embeddings) must carry ≥2 required files.
    const rcli::catalog::CatalogEntry* vlm = rcli::catalog::find("smolvlm2");
    if (!vlm || vlm->files == nullptr || vlm->file_count != 2) {
        result.details = "smolvlm2 should be a two-file artifact";
        return result;
    }

    result.passed = true;
    return result;
}

TestResult test_hf_ref_normalization() {
    TestResult result;
    result.test_name = "hf_ref_normalization";

    struct Case {
        std::string in;
        std::string expected;
    };
    const Case cases[] = {
        {"hf.co/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q8_0.gguf",
         "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf"},
        {"huggingface.co/org/repo/sub/dir/file.gguf",
         "https://huggingface.co/org/repo/resolve/main/sub/dir/file.gguf"},
        {"https://huggingface.co/org/repo/resolve/main/f.gguf",
         "https://huggingface.co/org/repo/resolve/main/f.gguf"},
        {"hf.co/org/repo", ""},      // needs an explicit file
        {"not-a-model-ref", ""},     // not an hf shorthand
        {"https://example.com/m.gguf", ""},
    };
    for (const Case& c : cases) {
        const std::string actual = rcli::model_ref::normalize_hf_ref(c.in);
        if (actual != c.expected) {
            result.expected = c.expected;
            result.actual = actual.empty() ? "<empty>" : actual;
            result.details = "input: " + c.in;
            return result;
        }
    }
    result.passed = true;
    return result;
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("rcli_unit");
    suite.add("json_escape", test_json_escape);
    suite.add("json_writer_shape", test_json_writer_shape);
    suite.add("human_bytes", test_human_bytes);
    suite.add("normalize_dir", test_normalize_dir);
    suite.add("resolve_home_precedence", test_resolve_home_precedence);
    suite.add("state_dir", test_state_dir);
    suite.add("catalog_lookup", test_catalog_lookup);
    suite.add("hf_ref_normalization", test_hf_ref_normalization);
    return suite.run(argc, argv);
}

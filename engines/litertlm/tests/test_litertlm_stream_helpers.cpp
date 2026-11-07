/** LiteRT-LM message JSON and stream assembly, independent of the LiteRT-LM library. */

#include "litertlm_stream_helpers.h"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

using litertlm_engine::ChunkText;
using litertlm_engine::parse_chunk;
using litertlm_engine::StreamAssembler;

namespace {

int g_failures = 0;

void expect_eq(const std::string& actual, const std::string& expected, const char* what) {
    if (actual != expected) {
        std::fprintf(stderr, "FAIL %s: got [%s], expected [%s]\n", what, actual.c_str(),
                     expected.c_str());
        ++g_failures;
    }
}

void expect_true(bool value, const char* what) {
    if (!value) {
        std::fprintf(stderr, "FAIL %s\n", what);
        ++g_failures;
    }
}

ChunkText answer(const std::string& text) {
    ChunkText chunk;
    chunk.answer = text;
    return chunk;
}

ChunkText reasoning(const std::string& text) {
    ChunkText chunk;
    chunk.reasoning = text;
    return chunk;
}

void test_parse_chunk() {
    expect_eq(parse_chunk(R"({"role":"assistant","content":[{"type":"text","text":"Hi"}]})").answer,
              "Hi", "answer chunk");
    const ChunkText thought =
        parse_chunk(R"({"role":"assistant","channels":{"thought":"Ok"},"reasoning_content":"Ok"})");
    expect_eq(thought.reasoning, "Ok", "reasoning chunk");
    expect_eq(thought.answer, "", "reasoning chunk has no answer");
    expect_eq(parse_chunk(R"({"content":"plain"})").answer, "plain", "string content");
    expect_eq(
        parse_chunk(R"({"content":[{"type":"text","text":"a"},{"type":"image"},{"text":"b"}]})")
            .answer,
        "ab", "text parts are joined and other parts skipped");
    expect_eq(parse_chunk("not json").answer, "", "garbage chunk");
    expect_eq(parse_chunk(R"(["array"])").answer, "", "non-object chunk");
}

void test_message_json() {
    expect_eq(litertlm_engine::to_json_string(litertlm_engine::text_message("user", "a\"b\n")),
              R"({"content":[{"text":"a\"b\n","type":"text"}],"role":"user"})", "escaping");
    const char* history[] = {"q1", "a1"};
    expect_eq(litertlm_engine::history_messages_json(history, 2),
              R"([{"content":[{"text":"q1","type":"text"}],"role":"user"},)"
              R"({"content":[{"text":"a1","type":"text"}],"role":"assistant"}])",
              "history alternates roles");
    expect_eq(litertlm_engine::system_content_json("be brief"),
              R"([{"text":"be brief","type":"text"}])", "system content has no role");
    const std::string invalid_utf8 =
        litertlm_engine::to_json_string(litertlm_engine::text_message("user", "bad\xC3"));
    expect_true(invalid_utf8.find("bad\xEF\xBF\xBD") != std::string::npos,
                "invalid UTF-8 is replaced, not thrown");
}

void test_reasoning_is_tagged() {
    StreamAssembler assembler({});
    expect_eq(assembler.feed(reasoning("think")), "<think>think", "opens the tag");
    expect_eq(assembler.feed(reasoning(" more")), " more", "tag stays open");
    expect_eq(assembler.feed(answer("Hi")), "</think>Hi", "answer closes the tag");
    expect_eq(assembler.finish(), "", "nothing left");

    StreamAssembler unfinished({});
    (void)unfinished.feed(reasoning("cut"));
    expect_eq(unfinished.finish(), "</think>", "the end closes an open tag");
}

void test_stop_sequences() {
    StreamAssembler split({"END"});
    expect_eq(split.feed(answer("abcE")), "abc", "holds a possible stop prefix");
    expect_eq(split.feed(answer("N")), "", "keeps holding");
    expect_eq(split.feed(answer("Dzzz")), "", "stop across chunks drops the rest");
    expect_true(split.stop_matched(), "stop across chunks matches");
    expect_eq(split.feed(answer("late")), "", "nothing after the stop");

    StreamAssembler released({"END"});
    expect_eq(released.feed(answer("xE")), "x", "holds E");
    expect_eq(released.feed(answer("y")), "Ey", "a failed prefix is released");
    expect_true(!released.stop_matched(), "no stop");

    StreamAssembler tail({"END"});
    expect_eq(tail.feed(answer("EN")), "", "holds EN");
    expect_eq(tail.finish(), "EN", "the end releases a held prefix");

    StreamAssembler same_chunk({"stop"});
    expect_eq(same_chunk.feed(answer("one stop two")), "one ", "text before the stop goes out");
    expect_true(same_chunk.stop_matched(), "stop within one chunk");

    StreamAssembler earliest({"b", "a"});
    expect_eq(earliest.feed(answer("xaby")), "x", "the earliest stop wins");

    StreamAssembler empty_stop({""});
    expect_eq(empty_stop.feed(answer("text")), "text", "an empty stop is ignored");
    expect_true(!empty_stop.stop_matched(), "an empty stop never matches");

    // A stop is matched on the answer only; reasoning may legitimately contain it.
    StreamAssembler reasoned({"END"});
    expect_eq(reasoned.feed(reasoning("END")), "<think>END", "reasoning is not scanned");
    expect_true(!reasoned.stop_matched(), "no stop in reasoning");

    // A held multi-byte prefix never comes out split.
    StreamAssembler multibyte({"\xE3\x80\x82\xE7\xB5\x82"});  // "。終"
    expect_eq(multibyte.feed(answer("\xE6\x97\xA5\xE3\x80\x82")), "\xE6\x97\xA5",
              "holds a whole character");
    expect_eq(multibyte.feed(answer("\xE6\x9C\xAC")), "\xE3\x80\x82\xE6\x9C\xAC",
              "releases whole characters");
}

void test_printable_ascii() {
    expect_eq(litertlm_engine::printable_ascii("ok \xFFmagic\n"), "ok magic", "raw bytes");
    expect_eq(litertlm_engine::printable_ascii("a]\n\xE2\x94\x94 ERROR"), "a] ERROR",
              "error chain");
    expect_eq(litertlm_engine::printable_ascii("a\xFF"
                                               "b"),
              "a b", "between words");
    expect_eq(litertlm_engine::printable_ascii(nullptr), "", "null");
    expect_eq(litertlm_engine::printable_ascii("abcdef", 3), "abc", "bounded");
}

// A bundle prefix with one section, whose FlatBuffer is laid out by hand:
//   0 root offset, 4 root vtable, 12 root table, 20 metadata vtable, 28 metadata table,
//   36 section vector, 44 section vtable, 56 section table with end_offset at 60.
std::string bundle_with_section_end(std::uint64_t end) {
    std::string flat(68, '\0');
    const auto put = [&flat](std::size_t position, auto value) {
        std::memcpy(&flat[position], &value, sizeof(value));
    };
    put(0, std::uint32_t{12});
    put(4, std::uint16_t{8});
    put(6, std::uint16_t{8});
    put(10, std::uint16_t{4});
    put(12, std::int32_t{8});
    put(16, std::uint32_t{12});
    put(20, std::uint16_t{6});
    put(22, std::uint16_t{8});
    put(24, std::uint16_t{4});
    put(28, std::int32_t{8});
    put(32, std::uint32_t{4});
    put(36, std::uint32_t{1});
    put(40, std::uint32_t{16});
    put(44, std::uint16_t{10});
    put(46, std::uint16_t{12});
    put(52, std::uint16_t{4});
    put(56, std::int32_t{12});
    put(60, end);

    std::string prefix(32, '\0');
    std::memcpy(&prefix[0], "LITERTLM", 8);
    const std::uint32_t major = 1;
    std::memcpy(&prefix[8], &major, sizeof(major));
    const std::uint64_t header_end = prefix.size() + flat.size();
    std::memcpy(&prefix[24], &header_end, sizeof(header_end));
    return prefix + flat;
}

std::uint64_t declared_size(const std::string& bytes) {
    std::istringstream stream(bytes);
    return litertlm_engine::bundle_declared_size(litertlm_engine::read_bundle_header(stream));
}

void test_bundle_declared_size() {
    const std::string bundle = bundle_with_section_end(5000);
    expect_true(declared_size(bundle) == 5000, "reads the end of the last section");
    expect_true(declared_size(bundle.substr(0, 40)) == bundle.size(), "ends inside its header");
    expect_true(declared_size("short") == 0, "too short for a prefix");
    expect_true(declared_size(std::string(100, 'x')) == 0, "no magic");

    std::string other_major = bundle;
    other_major[8] = 2;
    expect_true(declared_size(other_major) == 0, "unknown major version");

    // Offsets that lead nowhere fall back to the library's own checks.
    std::string bad = bundle;
    const std::uint32_t far = 100000;
    std::memcpy(&bad[32], &far, sizeof(far));
    expect_true(declared_size(bad) == 0, "root out of range");
    bad = bundle;
    std::memcpy(&bad[32 + 16], &far, sizeof(far));
    expect_true(declared_size(bad) == 0, "metadata out of range");
    bad = bundle;
    const std::int32_t behind = 1000;
    std::memcpy(&bad[32 + 12], &behind, sizeof(behind));
    expect_true(declared_size(bad) == 0, "vtable before the buffer");
}

// A bundle with an LlmMetadataProto section after its header. The FlatBuffer is the one above
// with begin_offset at 64, end_offset at 72 and data_type at 80.
std::string bundle_with_metadata(const std::string& metadata) {
    std::string flat(84, '\0');
    const auto put = [&flat](std::size_t position, auto value) {
        std::memcpy(&flat[position], &value, sizeof(value));
    };
    const std::uint64_t begin = 32 + flat.size();
    put(0, std::uint32_t{12});
    put(4, std::uint16_t{8});
    put(6, std::uint16_t{8});
    put(10, std::uint16_t{4});
    put(12, std::int32_t{8});
    put(16, std::uint32_t{12});
    put(20, std::uint16_t{6});
    put(22, std::uint16_t{8});
    put(24, std::uint16_t{4});
    put(28, std::int32_t{8});
    put(32, std::uint32_t{4});
    put(36, std::uint32_t{1});
    put(40, std::uint32_t{20});
    put(44, std::uint16_t{12});
    put(46, std::uint16_t{24});
    put(50, std::uint16_t{4});
    put(52, std::uint16_t{12});
    put(54, std::uint16_t{20});
    put(60, std::int32_t{16});
    put(64, begin);
    put(72, begin + metadata.size());
    put(80, std::uint8_t{5});

    std::string prefix(32, '\0');
    std::memcpy(&prefix[0], "LITERTLM", 8);
    const std::uint32_t major = 1;
    std::memcpy(&prefix[8], &major, sizeof(major));
    std::memcpy(&prefix[24], &begin, sizeof(begin));
    return prefix + flat + metadata;
}

std::string chat_template_of(const std::string& bytes) {
    std::istringstream stream(bytes);
    return litertlm_engine::bundle_chat_template(stream);
}

void test_bundle_chat_template() {
    // start_token (1, bytes), max_num_tokens (5, varint), a fixed32 (15), then the template (7).
    const std::string before = std::string("\x0a\x03\x12\x01x", 5) + "\x28\x80\x20" +
                               std::string("\x7d\x01\x02\x03\x04", 5);
    const std::string text(300, 't');
    const std::string field = std::string("\x3a\xac\x02", 3) + text;
    expect_eq(chat_template_of(bundle_with_metadata(before + field + "\x28\x01")), text,
              "finds the template among other fields");
    expect_eq(chat_template_of(bundle_with_metadata(before)), "", "no template");
    expect_eq(chat_template_of(bundle_with_metadata(before + field.substr(0, 100))), "",
              "a template that runs past the section");
    expect_eq(chat_template_of(bundle_with_metadata("\x3b")), "", "unknown wire type");
    expect_eq(chat_template_of(bundle_with_metadata("\x80")), "", "a key cut short");
    expect_eq(chat_template_of(bundle_with_section_end(5000)), "", "no metadata section");
    expect_eq(chat_template_of("short"), "", "not a bundle");
    const std::string whole = bundle_with_metadata(field);
    expect_eq(chat_template_of(whole.substr(0, whole.size() - 10)), "", "file cut short");
    expect_true(declared_size(whole) == whole.size(), "a metadata section counts for the size");
}

// A bundle with one model section whose items hold { key: value }, with a key of at most 10 bytes.
// The FlatBuffer starts as the one in bundle_with_section_end, with the items offset at 68, then
// 72 item vector, 80 item vtable, 92 item table, 108 value vtable, 116 value table, 124 key, 140
// value.
std::string bundle_with_item(const std::string& key, std::uint8_t value_type,
                             const std::string& value) {
    std::string flat(145 + value.size(), '\0');
    const auto put = [&flat](std::size_t position, auto number) {
        std::memcpy(&flat[position], &number, sizeof(number));
    };
    put(0, std::uint32_t{12});
    put(4, std::uint16_t{8});
    put(6, std::uint16_t{8});
    put(10, std::uint16_t{4});
    put(12, std::int32_t{8});
    put(16, std::uint32_t{12});
    put(20, std::uint16_t{6});
    put(22, std::uint16_t{8});
    put(24, std::uint16_t{4});
    put(28, std::int32_t{8});
    put(32, std::uint32_t{4});
    put(36, std::uint32_t{1});
    put(40, std::uint32_t{16});
    put(44, std::uint16_t{10});
    put(46, std::uint16_t{16});
    put(48, std::uint16_t{12});
    put(52, std::uint16_t{4});
    put(56, std::int32_t{12});
    put(60, std::uint64_t{5000});
    put(68, std::uint32_t{4});
    put(72, std::uint32_t{1});
    put(76, std::uint32_t{16});
    put(80, std::uint16_t{10});
    put(82, std::uint16_t{16});
    put(84, std::uint16_t{4});
    put(86, std::uint16_t{12});
    put(88, std::uint16_t{8});
    put(92, std::int32_t{12});
    put(96, std::uint32_t{28});
    put(100, std::uint32_t{16});
    put(104, value_type);
    put(108, std::uint16_t{6});
    put(110, std::uint16_t{8});
    put(112, std::uint16_t{4});
    put(116, std::int32_t{8});
    put(120, std::uint32_t{20});
    put(124, static_cast<std::uint32_t>(key.size()));
    flat.replace(128, key.size(), key);
    put(140, static_cast<std::uint32_t>(value.size()));
    flat.replace(144, value.size(), value);

    std::string prefix(32, '\0');
    std::memcpy(&prefix[0], "LITERTLM", 8);
    const std::uint32_t major = 1;
    std::memcpy(&prefix[8], &major, sizeof(major));
    const std::uint64_t header_end = prefix.size() + flat.size();
    std::memcpy(&prefix[24], &header_end, sizeof(header_end));
    return prefix + flat;
}

void test_bundle_model_types() {
    constexpr std::uint8_t kStringValue = 9;
    const auto first_model_type = [](const std::string& bytes) -> std::string {
        std::istringstream stream(bytes);
        const auto header = litertlm_engine::read_bundle_header(stream);
        return header.sections.empty() ? "?" : header.sections[0].model_type;
    };
    expect_eq(first_model_type(bundle_with_item("model_type", kStringValue, "tf_lite_aux")),
              "tf_lite_aux", "a model type");
    expect_eq(first_model_type(bundle_with_section_end(5000)), "", "no items");
    expect_eq(first_model_type(bundle_with_item("note", kStringValue, "tf_lite_aux")), "",
              "the name under another key");
    expect_eq(first_model_type(bundle_with_item("model_type", 1, "tf_lite_aux")), "",
              "a value that is not a string");

    // An item vector that claims more items than the header holds ends the walk.
    std::string long_vector = bundle_with_item("note", kStringValue, "tf_lite_aux");
    const std::uint32_t huge = 0xFFFFFFFFu;
    std::memcpy(&long_vector[32 + 72], &huge, sizeof(huge));
    expect_eq(first_model_type(long_vector), "", "an item count past the header");

    // A key or value longer than the header is not read.
    std::string long_text = bundle_with_item("model_type", kStringValue, "tf_lite_aux");
    std::memcpy(&long_text[32 + 140], &huge, sizeof(huge));
    expect_eq(first_model_type(long_text), "", "a string past the header");
}

// A TFLite model with a builtin op and one custom op, laid out by hand: 0 root offset, 4 model
// vtable, 12 model table, 24 operator code vector, 36 and 44 the vtables of the two codes,
// 40 and 52 their tables, 60 the custom op's name.
std::string tflite_with_custom_op(const std::string& custom) {
    std::string flat(65 + custom.size(), '\0');
    const auto put = [&flat](std::size_t position, auto number) {
        std::memcpy(&flat[position], &number, sizeof(number));
    };
    put(0, std::uint32_t{12});
    put(4, std::uint16_t{8});
    put(6, std::uint16_t{12});
    put(10, std::uint16_t{4});
    put(12, std::int32_t{8});
    put(16, std::uint32_t{8});
    put(24, std::uint32_t{2});
    put(28, std::uint32_t{12});
    put(32, std::uint32_t{20});
    put(36, std::uint16_t{4});
    put(38, std::uint16_t{4});
    put(40, std::int32_t{4});
    put(44, std::uint16_t{8});
    put(46, std::uint16_t{8});
    put(50, std::uint16_t{4});
    put(52, std::int32_t{8});
    put(56, std::uint32_t{4});
    put(60, static_cast<std::uint32_t>(custom.size()));
    flat.replace(64, custom.size(), custom);
    return flat;
}

void test_tflite_custom_op() {
    // The model sits 100 bytes into the file; `cut` takes bytes off the end of its section.
    const auto has = [](const std::string& model, const std::string& name, std::size_t cut) {
        const std::string bytes = std::string(100, 'x') + model;
        std::istringstream stream(bytes);
        return litertlm_engine::tflite_has_custom_op(stream, 100, 100 + model.size() - cut, name);
    };
    const std::string dispatch = tflite_with_custom_op("DISPATCH_OP");
    expect_true(has(dispatch, "DISPATCH_OP", 0), "the op");
    expect_true(!has(dispatch, "DISPATCH", 0), "a shorter name");
    expect_true(!has(tflite_with_custom_op("DISPATCH_OX"), "DISPATCH_OP", 0), "another op");
    expect_true(!has(dispatch, "DISPATCH_OP", 8), "a section that ends inside the name");

    // An operator code vector that claims more codes than the section holds ends the walk,
    // and one longer than any model's is not walked.
    std::string long_vector = tflite_with_custom_op("OTHER_OP");
    const std::uint32_t past_section = 100;
    std::memcpy(&long_vector[24], &past_section, sizeof(past_section));
    expect_true(!has(long_vector, "DISPATCH_OP", 0), "a code count past the section");
    const std::uint32_t huge = 0xFFFFFFFFu;
    std::memcpy(&long_vector[24], &huge, sizeof(huge));
    expect_true(!has(long_vector, "DISPATCH_OP", 0), "a code count past any model's");
}

void test_compiled_for_npu() {
    using litertlm_engine::BundleSection;
    const std::string dispatch = tflite_with_custom_op("DISPATCH_OP");
    const std::string other = tflite_with_custom_op("OTHER_OP");
    const std::string bytes = std::string(100, 'x') + dispatch + other;
    const std::uint64_t first = 100;
    const std::uint64_t second = first + dispatch.size();
    const std::uint64_t end = second + other.size();
    const auto section = [](std::uint64_t begin, std::uint64_t stop, const char* type) {
        BundleSection result;
        result.begin = begin;
        result.end = stop;
        result.data_type = 3;
        result.model_type = type;
        return result;
    };
    const auto compiled = [&bytes](const std::vector<BundleSection>& sections) {
        std::istringstream stream(bytes);
        return litertlm_engine::compiled_for_npu(stream, sections);
    };
    expect_true(compiled({section(second, end, "tf_lite_aux"),
                          section(first, second, "tf_lite_prefill_decode")}),
                "compiled for an NPU");
    expect_true(!compiled({section(first, second, "tf_lite_prefill_decode")}),
                "no auxiliary model");
    expect_true(!compiled({section(first, second, "tf_lite_aux"),
                           section(second, end, "tf_lite_prefill_decode")}),
                "built for an NPU but not compiled");
    expect_true(!compiled({section(second, second, "tf_lite_aux"),
                           section(first, second, "tf_lite_prefill_decode")}),
                "an empty auxiliary model");
}

}  // namespace

int main() {
    test_parse_chunk();
    test_message_json();
    test_reasoning_is_tagged();
    test_stop_sequences();
    test_printable_ascii();
    test_bundle_declared_size();
    test_bundle_chat_template();
    test_bundle_model_types();
    test_tflite_custom_op();
    test_compiled_for_npu();
    if (g_failures != 0) {
        std::fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    return 0;
}

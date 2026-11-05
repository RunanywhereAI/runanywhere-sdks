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
    return litertlm_engine::bundle_declared_size(stream);
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

}  // namespace

int main() {
    test_parse_chunk();
    test_message_json();
    test_reasoning_is_tagged();
    test_stop_sequences();
    test_printable_ascii();
    test_bundle_declared_size();
    test_bundle_chat_template();
    if (g_failures != 0) {
        std::fprintf(stderr, "%d failure(s)\n", g_failures);
        return 1;
    }
    return 0;
}

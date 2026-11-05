/**
 * @file litertlm_stream_helpers.h
 * @brief LiteRT-LM message JSON, stream assembly and reading a bundle's header.
 *
 * Header-only and free of the LiteRT-LM C API, so the logic is unit-tested on
 * every host whether or not the prebuilt library is present.
 */

#ifndef RUNANYWHERE_LITERTLM_STREAM_HELPERS_H
#define RUNANYWHERE_LITERTLM_STREAM_HELPERS_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <istream>
#include <nlohmann/json.hpp>
#include <string>
#include <utility>
#include <vector>

namespace litertlm_engine {

// Invalid UTF-8 in caller text becomes U+FFFD instead of a thrown type_error.
inline std::string to_json_string(const nlohmann::json& value) {
    return value.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
}

inline nlohmann::json text_message(const char* role, const char* text) {
    nlohmann::json part = nlohmann::json::object();
    part["type"] = "text";
    part["text"] = text != nullptr ? text : "";
    nlohmann::json message = nlohmann::json::object();
    message["role"] = role;
    message["content"] = nlohmann::json::array({part});
    return message;
}

// The value of litert_lm_conversation_config_set_system_message: the message
// content only, since the library adds the system role itself.
inline std::string system_content_json(const char* text) {
    nlohmann::json part = nlohmann::json::object();
    part["type"] = "text";
    part["text"] = text != nullptr ? text : "";
    return to_json_string(nlohmann::json::array({part}));
}

// rac_llm_options_t.history alternates user, assistant in chronological order.
inline std::string history_messages_json(const char* const* history, int32_t count) {
    nlohmann::json messages = nlohmann::json::array();
    for (int32_t i = 0; i < count; ++i) {
        messages.push_back(text_message(i % 2 == 0 ? "user" : "assistant", history[i]));
    }
    return to_json_string(messages);
}

// The text one stream chunk carries, by channel.
struct ChunkText {
    std::string answer;
    std::string reasoning;
};

// A chunk is a JSON message:
//   {"role":"assistant","content":[{"type":"text","text":"Hi"}]}
// or, on a thinking model's reasoning channel:
//   {"role":"assistant","channels":{"thought":"Ok"},"reasoning_content":"Ok"}
inline ChunkText parse_chunk(const std::string& json_text) {
    ChunkText out;
    const nlohmann::json message =
        nlohmann::json::parse(json_text, nullptr, /*allow_exceptions=*/false);
    if (!message.is_object()) {
        return out;
    }
    const auto reasoning = message.find("reasoning_content");
    if (reasoning != message.end() && reasoning->is_string()) {
        out.reasoning = reasoning->get<std::string>();
    }
    const auto content = message.find("content");
    if (content == message.end()) {
        return out;
    }
    if (content->is_string()) {
        out.answer = content->get<std::string>();
    } else if (content->is_array()) {
        for (const auto& part : *content) {
            const auto text = part.find("text");
            if (part.is_object() && text != part.end() && text->is_string()) {
                out.answer += text->get<std::string>();
            }
        }
    }
    return out;
}

// Turns chunks into the text the SDK receives.
//
// Commons splits reasoning from the answer by <think> tags in the stream, and
// LiteRT-LM reports it on a separate channel, so the channel is rendered as tags.
//
// Caller stop sequences apply to the answer only. A suffix that could still
// begin a stop sequence is held until the next chunk decides; since stop
// sequences begin on a character boundary, the held suffix does too, so the
// released text never splits a UTF-8 character.
class StreamAssembler {
   public:
    explicit StreamAssembler(std::vector<std::string> stop_sequences)
        : stops_(std::move(stop_sequences)) {
        stops_.erase(std::remove_if(stops_.begin(), stops_.end(),
                                    [](const std::string& stop) { return stop.empty(); }),
                     stops_.end());
    }

    std::string feed(const ChunkText& chunk) {
        std::string out;
        if (stop_matched_) {
            return out;
        }
        if (!chunk.reasoning.empty()) {
            if (!in_reasoning_) {
                out += "<think>";
                in_reasoning_ = true;
            }
            out += chunk.reasoning;
        }
        if (!chunk.answer.empty()) {
            if (in_reasoning_) {
                out += "</think>";
                in_reasoning_ = false;
            }
            held_ += chunk.answer;
            const std::size_t stop_at = earliest_stop();
            if (stop_at != std::string::npos) {
                out.append(held_, 0, stop_at);
                held_.clear();
                stop_matched_ = true;
                return out;
            }
            const std::size_t release = held_.size() - longest_possible_stop_prefix();
            out.append(held_, 0, release);
            held_.erase(0, release);
        }
        return out;
    }

    // The stream ended: whatever is still open or held goes out now.
    std::string finish() {
        std::string out;
        if (in_reasoning_) {
            out += "</think>";
            in_reasoning_ = false;
        }
        out += held_;
        held_.clear();
        return out;
    }

    bool stop_matched() const { return stop_matched_; }

   private:
    std::size_t earliest_stop() const {
        std::size_t earliest = std::string::npos;
        for (const auto& stop : stops_) {
            earliest = std::min(earliest, held_.find(stop));
        }
        return earliest;
    }

    std::size_t longest_possible_stop_prefix() const {
        std::size_t longest = 0;
        for (const auto& stop : stops_) {
            const std::size_t limit = std::min(stop.size() - 1, held_.size());
            for (std::size_t n = limit; n > longest; --n) {
                if (held_.compare(held_.size() - n, n, stop, 0, n) == 0) {
                    longest = n;
                    break;
                }
            }
        }
        return longest;
    }

    std::vector<std::string> stops_;
    std::string held_;
    bool in_reasoning_ = false;
    bool stop_matched_ = false;
};

// LiteRT-LM echoes raw file bytes into some load errors and draws its error chains
// with line breaks and box characters. Details cross JNI as modified UTF-8, so only
// printable ASCII goes through, with a space for each run of anything else.
inline std::string printable_ascii(const char* text, std::size_t max_length = 512) {
    std::string out;
    if (text == nullptr) {
        return out;
    }
    bool after_other = false;
    for (const char* p = text; *p != '\0' && out.size() < max_length; ++p) {
        const auto c = static_cast<unsigned char>(*p);
        if (c >= 0x20 && c < 0x7f) {
            if (after_other && !out.empty() && out.back() != ' ' && c != ' ') {
                out.push_back(' ');
            }
            out.push_back(static_cast<char>(c));
            after_other = false;
        } else {
            after_other = true;
        }
    }
    return out;
}

struct BundleSection {
    std::uint64_t begin = 0;
    std::uint64_t end = 0;
    std::uint8_t data_type = 0;
};

struct BundleHeader {
    std::uint64_t end = 0;
    bool cut_short = false;  // the file ends inside its own header
    std::vector<BundleSection> sections;
};

// Reads the section table of a .litertlm file. No sections when the header cannot be read:
// those files are left to the library, which reports them.
//
// Layout (schema/core/litertlm_header.h, litertlm_header_schema.fbs at v0.19.0): "LITERTLM",
// u32 major/minor/patch, 4 bytes of padding, u64 header end, then a little-endian FlatBuffer
//   LiteRTLMMetaData { system_metadata, section_metadata: { objects: [{ items, begin_offset,
//   end_offset, data_type }] } }.
// Read by hand so that this engine has no FlatBuffers dependency for a few fields.
inline BundleHeader read_bundle_header(std::istream& file) {
    constexpr std::size_t kPrefix = 32;
    constexpr std::uint64_t kMaxHeader = 16 * 1024;  // the library's kLitertLmHeaderMaxSize
    BundleHeader result;
    char prefix[kPrefix];
    if (!file.read(prefix, kPrefix) || std::memcmp(prefix, "LITERTLM", 8) != 0) {
        return result;
    }
    std::uint32_t major = 0;
    std::uint64_t header_end = 0;
    std::memcpy(&major, prefix + 8, sizeof(major));
    std::memcpy(&header_end, prefix + 24, sizeof(header_end));
    if (major != 1 || header_end <= kPrefix || header_end > kMaxHeader) {
        return result;
    }
    result.end = header_end;
    std::string header(static_cast<std::size_t>(header_end - kPrefix), '\0');
    if (!file.read(&header[0], static_cast<std::streamsize>(header.size()))) {
        result.cut_short = true;
        return result;
    }

    const auto read = [&header](std::size_t position, auto* out) {
        if (position > header.size() || header.size() - position < sizeof(*out)) {
            return false;
        }
        std::memcpy(out, header.data() + position, sizeof(*out));
        return true;
    };
    // Where field `index` of the table at `table` is stored; 0 when it is absent.
    const auto field = [&read](std::size_t table, std::size_t index) -> std::size_t {
        std::int32_t to_vtable = 0;
        std::uint16_t vtable_size = 0;
        std::uint16_t offset = 0;
        if (!read(table, &to_vtable)) {
            return 0;
        }
        const std::int64_t start = static_cast<std::int64_t>(table) - to_vtable;
        const std::size_t slot = 4 + 2 * index;
        if (start < 0 || !read(static_cast<std::size_t>(start), &vtable_size) ||
            slot >= vtable_size || !read(static_cast<std::size_t>(start) + slot, &offset)) {
            return 0;
        }
        return offset != 0 ? table + offset : 0;
    };
    // The object an offset stored at `position` refers to; 0 when there is none.
    const auto follow = [&read](std::size_t position) -> std::size_t {
        std::uint32_t offset = 0;
        return read(position, &offset) && offset != 0 ? position + offset : 0;
    };

    const std::size_t root = follow(0);
    const std::size_t section_metadata_field = root != 0 ? field(root, 1) : 0;
    const std::size_t section_metadata =
        section_metadata_field != 0 ? follow(section_metadata_field) : 0;
    const std::size_t objects_field = section_metadata != 0 ? field(section_metadata, 0) : 0;
    const std::size_t objects = objects_field != 0 ? follow(objects_field) : 0;
    std::uint32_t count = 0;
    if (objects == 0 || !read(objects, &count)) {
        return result;
    }
    std::vector<BundleSection> sections;
    for (std::uint32_t i = 0; i < count; ++i) {
        const std::size_t object = follow(objects + 4 + std::size_t{4} * i);
        const std::size_t end_field = object != 0 ? field(object, 2) : 0;
        BundleSection section;
        if (end_field == 0 || !read(end_field, &section.end)) {
            return result;
        }
        const std::size_t begin_field = field(object, 1);
        const std::size_t type_field = field(object, 3);
        if ((begin_field != 0 && !read(begin_field, &section.begin)) ||
            (type_field != 0 && !read(type_field, &section.data_type))) {
            return result;
        }
        sections.push_back(section);
    }
    result.sections = std::move(sections);
    return result;
}

// The size a .litertlm file declares: the end of its last section. Library v0.19.0 maps
// sections without checking the file reaches them, so a bundle cut short can end the
// process with SIGBUS instead of a load error. 0 when the header cannot be read.
inline std::uint64_t bundle_declared_size(std::istream& file) {
    const BundleHeader header = read_bundle_header(file);
    if (header.cut_short) {
        return header.end;
    }
    std::uint64_t declared = 0;
    for (const BundleSection& section : header.sections) {
        declared = std::max(declared, section.end);
    }
    return declared;
}

// The first length-delimited field `number` of a serialized protobuf message; empty when
// there is none or the message is malformed.
inline std::string protobuf_bytes_field(const std::string& message, std::uint64_t number) {
    std::size_t position = 0;
    const auto varint = [&message, &position](std::uint64_t* out) {
        *out = 0;
        for (int shift = 0; position < message.size() && shift < 64; shift += 7) {
            const auto byte = static_cast<unsigned char>(message[position++]);
            *out |= static_cast<std::uint64_t>(byte & 0x7fu) << shift;
            if ((byte & 0x80u) == 0) {
                return true;
            }
        }
        return false;
    };
    std::uint64_t key = 0;
    while (varint(&key)) {
        std::uint64_t value = 0;
        std::uint64_t skip = 0;
        switch (key & 7u) {
            case 0:
                if (!varint(&value)) {
                    return "";
                }
                break;
            case 1:
                skip = 8;
                break;
            case 2:
                if (!varint(&skip)) {
                    return "";
                }
                if ((key >> 3) == number && skip <= message.size() - position) {
                    return message.substr(position, static_cast<std::size_t>(skip));
                }
                break;
            case 5:
                skip = 4;
                break;
            default:
                return "";
        }
        if (skip > message.size() - position) {
            return "";
        }
        position += static_cast<std::size_t>(skip);
    }
    return "";
}

// The chat template a .litertlm file carries: LlmMetadata.jinja_prompt_template in its
// LlmMetadataProto section. Empty when it has none, or when the file cannot be read.
inline std::string bundle_chat_template(std::istream& file) {
    constexpr std::uint8_t kLlmMetadataProto = 5;  // AnySectionDataType
    constexpr std::uint64_t kJinjaPromptTemplate = 7;
    constexpr std::uint64_t kMaxMetadata = 1024 * 1024;
    const BundleHeader header = read_bundle_header(file);
    for (const BundleSection& section : header.sections) {
        if (section.data_type != kLlmMetadataProto || section.end <= section.begin ||
            section.end - section.begin > kMaxMetadata) {
            continue;
        }
        std::string metadata(static_cast<std::size_t>(section.end - section.begin), '\0');
        file.clear();
        file.seekg(static_cast<std::streamoff>(section.begin));
        if (!file.read(&metadata[0], static_cast<std::streamsize>(metadata.size()))) {
            return "";
        }
        return protobuf_bytes_field(metadata, kJinjaPromptTemplate);
    }
    return "";
}

}  // namespace litertlm_engine

#endif  // RUNANYWHERE_LITERTLM_STREAM_HELPERS_H

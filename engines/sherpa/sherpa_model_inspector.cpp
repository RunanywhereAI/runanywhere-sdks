#include "sherpa_model_inspector.h"

#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <limits>

#if !defined(_WIN32)
#include <sys/types.h>
#endif

namespace rac::backends::sherpa {
namespace {

#if defined(_WIN32)
using FileOffset = __int64;

FileOffset tell_file(FILE* file) {
    return _ftelli64(file);
}

bool seek_file(FILE* file, FileOffset offset, int origin) {
    return _fseeki64(file, offset, origin) == 0;
}
#else
using FileOffset = off_t;

FileOffset tell_file(FILE* file) {
    return ftello(file);
}

bool seek_file(FILE* file, FileOffset offset, int origin) {
    return fseeko(file, offset, origin) == 0;
}
#endif

class ProtoReader {
   public:
    ProtoReader(FILE* file, FileOffset end) : file_(file), end_(end) {}

    FileOffset position() const { return tell_file(file_); }
    bool exhausted() const { return position() < 0 || position() >= end_; }

    bool read_varint(uint64_t* value) {
        if (!value) {
            return false;
        }
        *value = 0;
        for (int shift = 0; shift < 64; shift += 7) {
            if (position() < 0 || position() >= end_) {
                return false;
            }
            const int byte = std::fgetc(file_);
            if (byte == EOF) {
                return false;
            }
            *value |= static_cast<uint64_t>(byte & 0x7f) << shift;
            if ((byte & 0x80) == 0) {
                return true;
            }
        }
        return false;
    }

    bool read_key(uint32_t* field, uint32_t* wire_type) {
        uint64_t key = 0;
        if (!read_varint(&key) || key == 0 || key > std::numeric_limits<uint32_t>::max()) {
            return false;
        }
        *field = static_cast<uint32_t>(key >> 3);
        *wire_type = static_cast<uint32_t>(key & 0x7);
        return *field != 0;
    }

    bool read_length(FileOffset* length) {
        uint64_t raw_length = 0;
        if (!read_varint(&raw_length) ||
            raw_length > static_cast<uint64_t>(std::numeric_limits<FileOffset>::max())) {
            return false;
        }
        *length = static_cast<FileOffset>(raw_length);
        const FileOffset current = position();
        return current >= 0 && *length >= 0 && *length <= end_ - current;
    }

    bool read_string(FileOffset length, std::string* value) {
        if (!value || length < 0 || length > 1024) {
            return false;
        }
        value->resize(static_cast<size_t>(length));
        return length == 0 || std::fread(value->data(), 1, static_cast<size_t>(length), file_) ==
                                  static_cast<size_t>(length);
    }

    bool skip(FileOffset bytes) {
        const FileOffset current = position();
        return current >= 0 && bytes >= 0 && bytes <= end_ - current &&
               seek_file(file_, current + bytes, SEEK_SET);
    }

    bool skip_field(uint32_t wire_type) {
        switch (wire_type) {
            case 0: {
                uint64_t ignored = 0;
                return read_varint(&ignored);
            }
            case 1:
                return skip(8);
            case 2: {
                FileOffset length = 0;
                return read_length(&length) && skip(length);
            }
            case 5:
                return skip(4);
            default:
                return false;
        }
    }

   private:
    FILE* file_;
    FileOffset end_;
};

bool read_value_info_name(FILE* file, FileOffset end, std::string* name) {
    ProtoReader reader(file, end);
    while (!reader.exhausted()) {
        uint32_t field = 0;
        uint32_t wire_type = 0;
        if (!reader.read_key(&field, &wire_type)) {
            return false;
        }
        if (field == 1 && wire_type == 2) {
            FileOffset length = 0;
            return reader.read_length(&length) && reader.read_string(length, name);
        }
        if (!reader.skip_field(wire_type)) {
            return false;
        }
    }
    return false;
}

SherpaOnnxEncoderContract inspect_graph(FILE* file, FileOffset graph_end) {
    ProtoReader reader(file, graph_end);
    bool saw_graph_input = false;
    bool saw_channel_cache = false;
    bool saw_time_cache = false;
    bool saw_cache_length = false;
    bool saw_prompt_index = false;

    while (!reader.exhausted()) {
        uint32_t field = 0;
        uint32_t wire_type = 0;
        if (!reader.read_key(&field, &wire_type)) {
            return {};
        }

        // onnx.GraphProto.input is repeated ValueInfoProto field 11.
        if (field == 11 && wire_type == 2) {
            FileOffset length = 0;
            if (!reader.read_length(&length)) {
                return {};
            }
            const FileOffset value_end = reader.position() + length;
            std::string name;
            if (!read_value_info_name(file, value_end, &name) ||
                !seek_file(file, value_end, SEEK_SET)) {
                return {};
            }
            saw_graph_input = true;
            saw_channel_cache = saw_channel_cache || name == "cache_last_channel";
            saw_time_cache = saw_time_cache || name == "cache_last_time";
            saw_cache_length = saw_cache_length || name == "cache_last_channel_len";
            saw_prompt_index = saw_prompt_index || name == "prompt_index";
            continue;
        }

        if (!reader.skip_field(wire_type)) {
            return {};
        }
    }

    if (!saw_graph_input) {
        return {};
    }
    const bool online = saw_channel_cache && saw_time_cache && saw_cache_length;
    return {
        .kind = online ? SherpaOnnxEncoderKind::OnlineTransducer : SherpaOnnxEncoderKind::Offline,
        .uses_language_prompt = online && saw_prompt_index,
    };
}

std::array<int, 3> parse_version(std::string_view version, bool* valid) {
    std::array<int, 3> parts{};
    size_t cursor = 0;
    while (cursor < version.size() && !std::isdigit(static_cast<unsigned char>(version[cursor]))) {
        ++cursor;
    }
    for (size_t part = 0; part < parts.size(); ++part) {
        if (cursor >= version.size() ||
            !std::isdigit(static_cast<unsigned char>(version[cursor]))) {
            *valid = false;
            return {};
        }
        int value = 0;
        while (cursor < version.size() &&
               std::isdigit(static_cast<unsigned char>(version[cursor]))) {
            const int digit = version[cursor++] - '0';
            if (value > (std::numeric_limits<int>::max() - digit) / 10) {
                *valid = false;
                return {};
            }
            value = value * 10 + digit;
        }
        parts[part] = value;
        if (part + 1 < parts.size()) {
            if (cursor >= version.size() || version[cursor] != '.') {
                *valid = false;
                return {};
            }
            ++cursor;
        }
    }
    *valid = true;
    return parts;
}

}  // namespace

SherpaOnnxEncoderContract inspect_sherpa_onnx_encoder(const std::string& encoder_path) {
    FILE* file = std::fopen(encoder_path.c_str(), "rb");
    if (!file) {
        return {};
    }

    if (!seek_file(file, 0, SEEK_END)) {
        std::fclose(file);
        return {};
    }
    const FileOffset file_end = tell_file(file);
    if (file_end <= 0 || !seek_file(file, 0, SEEK_SET)) {
        std::fclose(file);
        return {};
    }

    ProtoReader reader(file, file_end);
    SherpaOnnxEncoderContract contract;
    while (!reader.exhausted()) {
        uint32_t field = 0;
        uint32_t wire_type = 0;
        if (!reader.read_key(&field, &wire_type)) {
            break;
        }

        // onnx.ModelProto.graph is field 7.
        if (field == 7 && wire_type == 2) {
            FileOffset length = 0;
            if (!reader.read_length(&length)) {
                break;
            }
            const FileOffset graph_end = reader.position() + length;
            contract = inspect_graph(file, graph_end);
            break;
        }

        if (!reader.skip_field(wire_type)) {
            break;
        }
    }

    std::fclose(file);
    return contract;
}

bool sherpa_runtime_version_at_least(std::string_view version, int required_major,
                                     int required_minor, int required_patch) {
    bool valid = false;
    const std::array<int, 3> actual = parse_version(version, &valid);
    if (!valid) {
        return false;
    }
    return actual >= std::array<int, 3>{required_major, required_minor, required_patch};
}

}  // namespace rac::backends::sherpa

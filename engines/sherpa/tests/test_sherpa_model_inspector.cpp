#include "sherpa_model_inspector.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

void append_varint(uint64_t value, std::vector<uint8_t>* out) {
    while (value >= 0x80) {
        out->push_back(static_cast<uint8_t>(value & 0x7f) | 0x80);
        value >>= 7;
    }
    out->push_back(static_cast<uint8_t>(value));
}

void append_message(uint32_t field, const std::vector<uint8_t>& message,
                    std::vector<uint8_t>* out) {
    append_varint((static_cast<uint64_t>(field) << 3) | 2, out);
    append_varint(message.size(), out);
    out->insert(out->end(), message.begin(), message.end());
}

void append_string(uint32_t field, const std::string& value, std::vector<uint8_t>* out) {
    append_varint((static_cast<uint64_t>(field) << 3) | 2, out);
    append_varint(value.size(), out);
    out->insert(out->end(), value.begin(), value.end());
}

std::vector<uint8_t> encoder_fixture(const std::vector<std::string>& input_names) {
    std::vector<uint8_t> graph;
    for (const std::string& name : input_names) {
        std::vector<uint8_t> value_info;
        append_string(1, name, &value_info);     // ValueInfoProto.name
        append_message(11, value_info, &graph);  // GraphProto.input
    }
    std::vector<uint8_t> model;
    append_message(7, graph, &model);  // ModelProto.graph
    return model;
}

bool write_fixture(const std::filesystem::path& path, const std::vector<uint8_t>& bytes) {
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    stream.write(reinterpret_cast<const char*>(bytes.data()),
                 static_cast<std::streamsize>(bytes.size()));
    return stream.good();
}

bool expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
    }
    return condition;
}

}  // namespace

int main(int argc, char** argv) {
    using rac::backends::sherpa::inspect_sherpa_onnx_encoder;
    using rac::backends::sherpa::sherpa_runtime_version_at_least;
    using rac::backends::sherpa::SherpaOnnxEncoderKind;

    const std::filesystem::path temp_dir =
        std::filesystem::temp_directory_path() / "runanywhere-sherpa-inspector";
    std::filesystem::create_directories(temp_dir);
    const std::filesystem::path online_path = temp_dir / "online.onnx";
    const std::filesystem::path offline_path = temp_dir / "offline.onnx";

    bool ok = true;
    ok &= expect(
        write_fixture(online_path, encoder_fixture({"audio_signal", "length", "cache_last_channel",
                                                    "cache_last_time", "cache_last_channel_len",
                                                    "prompt_index"})),
        "write online fixture");
    ok &= expect(write_fixture(offline_path, encoder_fixture({"audio_signal", "length"})),
                 "write offline fixture");

    const auto online = inspect_sherpa_onnx_encoder(online_path.string());
    ok &= expect(online.kind == SherpaOnnxEncoderKind::OnlineTransducer,
                 "streaming cache inputs identify an online transducer");
    ok &= expect(online.uses_language_prompt, "prompt_index identifies multilingual prompt state");

    const auto offline = inspect_sherpa_onnx_encoder(offline_path.string());
    ok &= expect(offline.kind == SherpaOnnxEncoderKind::Offline,
                 "non-streaming encoder remains offline");
    ok &= expect(!offline.uses_language_prompt, "offline encoder has no prompt state");

    const auto missing = inspect_sherpa_onnx_encoder((temp_dir / "missing.onnx").string());
    ok &= expect(missing.kind == SherpaOnnxEncoderKind::Unknown,
                 "unreadable encoder is not misclassified");

    ok &=
        expect(sherpa_runtime_version_at_least("1.13.4", 1, 13, 4), "exact minimum version passes");
    ok &= expect(sherpa_runtime_version_at_least("v1.14.0-dev", 1, 13, 4),
                 "newer tagged version passes");
    ok &= expect(!sherpa_runtime_version_at_least("1.13.2", 1, 13, 4),
                 "older native runtime fails closed");
    ok &= expect(!sherpa_runtime_version_at_least("unknown", 1, 13, 4),
                 "unparseable runtime version fails closed");

    if (argc > 1) {
        const auto external = inspect_sherpa_onnx_encoder(argv[1]);
        ok &= expect(external.kind == SherpaOnnxEncoderKind::OnlineTransducer,
                     "external encoder has the online transducer cache contract");
        ok &= expect(external.uses_language_prompt,
                     "external encoder exposes the language prompt input");
    }

    std::filesystem::remove_all(temp_dir);
    if (ok) {
        std::cout << "Sherpa model inspector tests passed\n";
        return 0;
    }
    return 1;
}

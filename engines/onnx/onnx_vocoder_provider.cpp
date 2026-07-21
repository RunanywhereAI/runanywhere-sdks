/** @file onnx_vocoder_provider.cpp @brief Exact NVIDIA BigVGAN ONNX pipeline. */

#include "onnx_vocoder_provider.h"

#include "rac_runtime_onnxrt.h"

#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <mutex>
#include <new>
#include <nlohmann/json.hpp>
#include <string>
#include <utility>
#include <vector>

#if defined(__EMSCRIPTEN__)
#include <emscripten.h>
#endif

#include "rac/core/rac_logger.h"
#include "rac/foundation/rac_sha256.h"

namespace runanywhere::vocoder {
namespace {

using json = nlohmann::json;
using runanywhere::runtime::onnxrt::ElementType;
using runanywhere::runtime::onnxrt::Session;
using runanywhere::runtime::onnxrt::SessionOptions;
using runanywhere::runtime::onnxrt::TensorInput;
using runanywhere::runtime::onnxrt::TensorOutput;

constexpr const char* kLogCategory = "Vocoder.ONNX";
constexpr const char* kBundleManifestName = "runanywhere-export-manifest.json";
constexpr const char* kModelFileName = "model.onnx";
constexpr const char* kDataFileName = "model.onnx.data";
constexpr const char* kConfigFileName = "config.json";
constexpr const char* kLicenseFileName = "LICENSE";
constexpr const char* kSchema = "runanywhere-bigvgan-onnx-bundle/v1";
constexpr uint32_t kMelBinCount = 80;
constexpr uint32_t kChannelCount = 1;
constexpr uint32_t kSampleRateHz = 22050;
constexpr uint32_t kHopLength = 256;
constexpr uint64_t kMaxBatchFrames = 65536;

#if defined(__EMSCRIPTEN__)
class ScopedExternalDataMount final {
   public:
    explicit ScopedExternalDataMount(const std::filesystem::path& path)
        : path_(path.lexically_normal().generic_string()) {}

    ScopedExternalDataMount(const ScopedExternalDataMount&) = delete;
    ScopedExternalDataMount& operator=(const ScopedExternalDataMount&) = delete;

    ~ScopedExternalDataMount() { reset(); }

    bool mount(std::string* error) {
        // clang-format off: this body is JavaScript consumed by Emscripten.
        const int result = EM_ASM_INT(
            {
                const filePath = UTF8ToString($0);
                try {
                    if (typeof FS === 'undefined' || typeof FS.lookupPath !== 'function') {
                        return 1;
                    }
                    const node = FS.lookupPath(filePath, { follow: true }).node;
                    if (!node || !FS.isFile(node.mode)) {
                        return 2;
                    }
                    const contents = node.contents;
                    const usedBytes = node.usedBytes;
                    if (!(contents instanceof Uint8Array) || !Number.isSafeInteger(usedBytes) ||
                        usedBytes < 0 || usedBytes > contents.byteLength) {
                        return 3;
                    }
                    let mountedFiles = Module['MountedFiles'];
                    if (mountedFiles === undefined) {
                        mountedFiles = new Map();
                        Module['MountedFiles'] = mountedFiles;
                    }
                    if (typeof mountedFiles.set !== 'function' ||
                        typeof mountedFiles.has !== 'function' ||
                        typeof mountedFiles.delete !== 'function') {
                        return 4;
                    }
                    // Never replace an entry owned by ORT or another session.
                    // Session creation is synchronous; callers may retry after
                    // the current mount has left this short critical section.
                    if (mountedFiles.has(filePath)) {
                        return 6;
                    }
                    // MEMFS owns `contents`; subarray creates only a view, not a
                    // second approximately 449 MB copy of BigVGAN's external data.
                    mountedFiles.set(filePath, contents.subarray(0, usedBytes));
                    return 0;
                } catch {
                    return 5;
                }
            },
            path_.c_str());
        // clang-format on
        if (result == 0) {
            mounted_ = true;
            return true;
        }
        if (error) {
            switch (result) {
                case 1:
                    *error = "Emscripten FS is unavailable";
                    break;
                case 2:
                    *error = "external data is not a regular Emscripten file";
                    break;
                case 3:
                    *error = "external data is not backed by a valid zero-copy MEMFS view";
                    break;
                case 4:
                    *error = "Module.MountedFiles is not Map-compatible";
                    break;
                case 6:
                    *error = "external data path is already mounted by another ONNX session";
                    break;
                default:
                    *error = "cannot expose external data to ONNX Runtime WASM";
                    break;
            }
        }
        return false;
    }

    void reset() noexcept {
        if (!mounted_) {
            return;
        }
        // clang-format off: this body is JavaScript consumed by Emscripten.
        EM_ASM(
            {
                const filePath = UTF8ToString($0);
                try {
                    const mountedFiles =
                        typeof Module === 'undefined' ? undefined : Module['MountedFiles'];
                    if (mountedFiles && typeof mountedFiles.delete === 'function') {
                        mountedFiles.delete(filePath);
                    }
                } catch {
                    // Destructors must not throw. The MEMFS node remains owned by FS;
                    // this cleanup only releases ORT's temporary zero-copy view.
                }
            },
            path_.c_str());
        // clang-format on
        mounted_ = false;
    }

   private:
    std::string path_;
    bool mounted_ = false;
};
#endif

#if defined(RAC_VOCODER_TEST_FIXTURE_BUNDLE)
constexpr const char* kSourceModelRepo = "runanywhere/test-bigvgan-tiny";
constexpr const char* kSourceModelRevision =
    "380bec35b30286b1fe78549c9c3cc87b2a2eb09d50310628440e380d90fc4da1";
constexpr const char* kSourceCodeRepo = "runanywhere/test-bigvgan-tiny";
constexpr const char* kSourceCodeRevision = kSourceModelRevision;
constexpr uintmax_t kManifestSize = 865;
constexpr const char* kManifestSha256 =
    "9b3ae8c4e1f8b60da6a5848b7a203fdaabeb1cfb185b70ac2baedbe54d460618";
constexpr uintmax_t kModelSize = 409;
constexpr const char* kModelSha256 =
    "380bec35b30286b1fe78549c9c3cc87b2a2eb09d50310628440e380d90fc4da1";
constexpr uintmax_t kConfigSize = 76;
constexpr const char* kConfigSha256 =
    "f748ff8cf486210f683eceec0d0cbbbdd9717baff7d767591bc323ee38437385";
constexpr uintmax_t kLicenseSize = 73;
constexpr const char* kLicenseSha256 =
    "dc8b24d94a76066c769f73a3ee7ff413be815dc96d4a073e0a4b090e0b88d225";
constexpr bool kRequiresExternalData = false;
constexpr uintmax_t kDataSize = 0;
constexpr const char* kDataSha256 = "";
#else
constexpr const char* kSourceModelRepo = "nvidia/bigvgan_v2_22khz_80band_256x";
constexpr const char* kSourceModelRevision = "633ff708ed5b74903e86ff1298cf4a98e921c513";
constexpr const char* kSourceCodeRepo = "NVIDIA/BigVGAN";
constexpr const char* kSourceCodeRevision = "7d2b454564a6c7d014227f635b7423881f14bdac";
constexpr uintmax_t kManifestSize = 6138;
constexpr const char* kManifestSha256 =
    "f0461fe73057c5b1a8def5d8f5a428c0577b470a52ac4d088dba8b2ae6093d86";
constexpr uintmax_t kModelSize = 1720451;
constexpr const char* kModelSha256 =
    "0b1e76c36e90ad0036b7ca09d435aca5da595dd71ac687e1e54abc6fcc4f93b7";
constexpr uintmax_t kDataSize = 448717824;
constexpr const char* kDataSha256 =
    "fc30a80656db48e1bee556180cef53444c198283ee3e72b480b68822102470a0";
constexpr uintmax_t kConfigSize = 1405;
constexpr const char* kConfigSha256 =
    "88a1f47acf747db0b21e97a389d838566147f7a5464583ff5c8d819d870f03ee";
constexpr uintmax_t kLicenseSize = 1076;
constexpr const char* kLicenseSha256 =
    "90459cd52fc41bd723df7c0c76fac1e4dd60e6bfd644a7e2a93f325bed4f6d95";
constexpr bool kRequiresExternalData = true;
#endif

bool checked_mul(size_t a, size_t b, size_t* out) {
    if (!out || (a != 0 && b > std::numeric_limits<size_t>::max() / a)) {
        return false;
    }
    *out = a * b;
    return true;
}

bool read_file(const std::filesystem::path& path, std::string* out) {
    if (!out) {
        return false;
    }
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        return false;
    }
    out->assign(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
    return stream.good() || stream.eof();
}

bool sha256_file(const std::filesystem::path& path, std::string* out) {
    if (!out) {
        return false;
    }
    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        return false;
    }
    runanywhere::sha256_ctx context;
    runanywhere::sha256_init(&context);
    std::array<uint8_t, 64 * 1024> buffer{};
    while (stream) {
        stream.read(reinterpret_cast<char*>(buffer.data()), buffer.size());
        const auto count = stream.gcount();
        if (count > 0) {
            runanywhere::sha256_update(&context, buffer.data(), static_cast<size_t>(count));
        }
    }
    if (!stream.eof()) {
        return false;
    }
    uint8_t digest[32] = {};
    runanywhere::sha256_final(&context, digest);
    *out = runanywhere::bytes_to_hex(digest, sizeof(digest));
    return true;
}

bool validate_file(const std::filesystem::path& path, const json& artifacts,
                   const char* artifact_name, uintmax_t expected_size, const char* expected_sha,
                   std::string* error) {
    try {
        if (!std::filesystem::is_regular_file(path) ||
            std::filesystem::file_size(path) != expected_size) {
            *error = std::string(artifact_name) + " has the wrong pinned byte size";
            return false;
        }
    } catch (...) {
        *error = std::string("cannot inspect ") + artifact_name;
        return false;
    }
    const auto it = artifacts.find(artifact_name);
    if (it == artifacts.end() || !it->is_object() ||
        it->value("size_bytes", uintmax_t{0}) != expected_size ||
        it->value("sha256", std::string()) != expected_sha) {
        *error = std::string("manifest does not pin ") + artifact_name;
        return false;
    }
    std::string actual;
    if (!sha256_file(path, &actual) || actual != expected_sha) {
        *error = std::string(artifact_name) + " checksum does not match the pinned bundle";
        return false;
    }
    return true;
}

bool exact_shape(const json& value, const std::array<json, 3>& expected) {
    if (!value.is_array() || value.size() != expected.size()) {
        return false;
    }
    for (size_t i = 0; i < expected.size(); ++i) {
        if (value[i] != expected[i]) {
            return false;
        }
    }
    return true;
}

bool load_and_validate_bundle_impl(const std::filesystem::path& directory,
                                   std::filesystem::path* out_model, std::string* error) {
    if (!out_model || !error) {
        return false;
    }
    const auto manifest_path = directory / kBundleManifestName;
    const auto model_path = directory / kModelFileName;
    const auto data_path = directory / kDataFileName;
    const auto config_path = directory / kConfigFileName;
    const auto license_path = directory / kLicenseFileName;
    try {
        if (!std::filesystem::is_regular_file(manifest_path) ||
            std::filesystem::file_size(manifest_path) != kManifestSize) {
            *error = "runanywhere-export-manifest.json has the wrong pinned byte size";
            return false;
        }
    } catch (...) {
        *error = "cannot inspect the BigVGAN bundle manifest";
        return false;
    }
    std::string manifest_sha;
    std::string manifest_bytes;
    std::string config_bytes;
    if (!sha256_file(manifest_path, &manifest_sha) || manifest_sha != kManifestSha256 ||
        !read_file(manifest_path, &manifest_bytes) || !read_file(config_path, &config_bytes)) {
        *error = "cannot read or verify the pinned BigVGAN manifest/config";
        return false;
    }

    json manifest;
    json config;
    try {
        manifest = json::parse(manifest_bytes);
        config = json::parse(config_bytes);
    } catch (const std::exception& exception) {
        *error = std::string("invalid BigVGAN JSON: ") + exception.what();
        return false;
    }
    const auto& source_model = manifest.value("source_model", json::object());
    const auto& source_code = manifest.value("source_code", json::object());
    const auto& contract = manifest.value("contract", json::object());
    const auto& input = contract.value("input", json::object());
    const auto& output = contract.value("output", json::object());
    const auto& artifacts = manifest.value("artifacts", json::object());
    const bool identity =
        manifest.value("schema", std::string()) == kSchema && source_model.is_object() &&
        source_model.value("repository", std::string()) == kSourceModelRepo &&
        source_model.value("revision", std::string()) == kSourceModelRevision &&
        source_code.is_object() &&
        source_code.value("repository", std::string()) == kSourceCodeRepo &&
        source_code.value("revision", std::string()) == kSourceCodeRevision &&
        contract.is_object() && contract.value("hop_length", 0U) == kHopLength &&
        contract.value("sample_rate_hz", 0U) == kSampleRateHz && input.is_object() &&
        input.value("name", std::string()) == "mel_spectrogram" &&
        input.value("dtype", std::string()) == "float32" &&
        exact_shape(input.value("shape", json::array()), {"B", 80, "T"}) && output.is_object() &&
        output.value("name", std::string()) == "audio_waveform" &&
        output.value("dtype", std::string()) == "float32" &&
        exact_shape(output.value("shape", json::array()), {"B", 1, "256*T"}) &&
        artifacts.is_object();
    if (!identity) {
        *error = "bundle manifest does not identify the exact BigVGAN 22 kHz contract";
        return false;
    }
    if (!validate_file(model_path, artifacts, kModelFileName, kModelSize, kModelSha256, error) ||
        (kRequiresExternalData &&
         !validate_file(data_path, artifacts, kDataFileName, kDataSize, kDataSha256, error)) ||
        !validate_file(config_path, artifacts, kConfigFileName, kConfigSize, kConfigSha256,
                       error) ||
        !validate_file(license_path, artifacts, kLicenseFileName, kLicenseSize, kLicenseSha256,
                       error)) {
        return false;
    }
    const auto model_type = config.find("model_type");
    if ((model_type != config.end() && (!model_type->is_string() || *model_type != "bigvgan")) ||
        config.value("num_mels", 0U) != kMelBinCount ||
        config.value("hop_size", 0U) != kHopLength ||
        config.value("sampling_rate", 0U) != kSampleRateHz) {
        *error = "config.json is not the exact 80-mel, 22.05 kHz BigVGAN contract";
        return false;
    }
    *out_model = model_path;
    return true;
}

bool load_and_validate_bundle(const std::filesystem::path& directory,
                              std::filesystem::path* out_model, std::string* error) {
    try {
        return load_and_validate_bundle_impl(directory, out_model, error);
    } catch (const std::bad_alloc&) {
        throw;
    } catch (const std::exception& exception) {
        if (error) {
            *error = std::string("invalid BigVGAN bundle: ") + exception.what();
        }
        return false;
    } catch (...) {
        if (error) {
            *error = "invalid BigVGAN bundle";
        }
        return false;
    }
}

}  // namespace

class ONNXVocoderProvider::Impl {
   public:
    std::unique_ptr<Session> session;
    mutable std::mutex mutex;
};

ONNXVocoderProvider::ONNXVocoderProvider() : impl_(std::make_unique<Impl>()) {}
ONNXVocoderProvider::~ONNXVocoderProvider() = default;

rac_result_t ONNXVocoderProvider::initialize(const std::string& model_path) {
    try {
        std::filesystem::path supplied(model_path);
        std::filesystem::path directory =
            std::filesystem::is_directory(supplied) ? supplied : supplied.parent_path();
        if (directory.empty()) {
            directory = ".";
        }
        std::filesystem::path model;
        std::string error;
        if (!load_and_validate_bundle(directory, &model, &error)) {
            RAC_LOG_ERROR(kLogCategory, "BigVGAN bundle rejected: %s", error.c_str());
            return RAC_ERROR_MODEL_VALIDATION_FAILED;
        }
        SessionOptions options;
        options.log_id = "RunAnywhereBigVGAN";
#if defined(__EMSCRIPTEN__)
        ScopedExternalDataMount external_data_mount(model.parent_path() / kDataFileName);
        if (kRequiresExternalData && !external_data_mount.mount(&error)) {
            RAC_LOG_ERROR(kLogCategory, "BigVGAN external data mount failed: %s", error.c_str());
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
#endif
        auto session = Session::create(model.string(), options, &error);
#if defined(__EMSCRIPTEN__)
        // ORT consumes external initializers synchronously during session creation.
        // Match its Web API lifetime and release only this provider's temporary entry.
        external_data_mount.reset();
#endif
        if (!session) {
            RAC_LOG_ERROR(kLogCategory, "BigVGAN ORT session creation failed: %s", error.c_str());
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        std::lock_guard<std::mutex> lock(impl_->mutex);
        impl_->session = std::move(session);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (const std::exception& exception) {
        RAC_LOG_ERROR(kLogCategory, "BigVGAN bundle rejected: %s", exception.what());
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    } catch (...) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
}

rac_result_t ONNXVocoderProvider::vocode(const rac_vocoder_input_t& input,
                                         rac_vocoder_result_t* out_result) {
    if (!out_result || !input.mel_spectrogram || input.batch_size == 0 ||
        input.mel_bin_count != kMelBinCount || input.frame_count == 0 ||
        static_cast<uint64_t>(input.batch_size) * input.frame_count > kMaxBatchFrames) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_result = {};
    size_t batch_mels = 0;
    size_t input_values = 0;
    if (!checked_mul(input.batch_size, input.mel_bin_count, &batch_mels) ||
        !checked_mul(batch_mels, input.frame_count, &input_values) ||
        input.value_count != input_values) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    for (size_t i = 0; i < input_values; ++i) {
        if (!std::isfinite(input.mel_spectrogram[i])) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
    }
    size_t samples_per_batch = 0;
    size_t output_values = 0;
    if (!checked_mul(input.frame_count, kHopLength, &samples_per_batch) ||
        samples_per_batch > std::numeric_limits<uint32_t>::max() ||
        !checked_mul(input.batch_size, samples_per_batch, &output_values)) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    std::lock_guard<std::mutex> lock(impl_->mutex);
    if (!impl_->session) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }
    const auto started = std::chrono::steady_clock::now();
    const int64_t input_shape[] = {static_cast<int64_t>(input.batch_size), kMelBinCount,
                                   static_cast<int64_t>(input.frame_count)};
    const TensorInput tensor = {
        .name = "mel_spectrogram",
        .data = input.mel_spectrogram,
        .data_bytes = input_values * sizeof(float),
        .shape = input_shape,
        .rank = 3,
        .type = ElementType::Float32,
    };
    const char* output_names[] = {"audio_waveform"};
    std::vector<TensorOutput> outputs;
    std::string error;
    rac_result_t rc = impl_->session->run(&tensor, 1, output_names, 1, outputs, &error);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(kLogCategory, "BigVGAN inference failed: %s", error.c_str());
        return rc;
    }
    const std::vector<int64_t> expected_shape = {static_cast<int64_t>(input.batch_size), 1,
                                                 static_cast<int64_t>(samples_per_batch)};
    size_t output_bytes = 0;
    if (!checked_mul(output_values, sizeof(float), &output_bytes) || outputs.size() != 1 ||
        outputs[0].dtype != ElementType::Float32 || outputs[0].shape != expected_shape ||
        outputs[0].bytes.size() != output_bytes) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    out_result->samples = static_cast<float*>(std::malloc(output_bytes));
    if (!out_result->samples) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    std::memcpy(out_result->samples, outputs[0].bytes.data(), output_bytes);
    for (size_t i = 0; i < output_values; ++i) {
        if (!std::isfinite(out_result->samples[i])) {
            rac_vocoder_result_free(out_result);
            return RAC_ERROR_MODEL_VALIDATION_FAILED;
        }
    }
    out_result->sample_value_count = output_values;
    out_result->batch_size = input.batch_size;
    out_result->channel_count = kChannelCount;
    out_result->sample_count = static_cast<uint32_t>(samples_per_batch);
    out_result->sample_rate_hz = kSampleRateHz;
    out_result->hop_length = kHopLength;
    out_result->processing_time_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                         std::chrono::steady_clock::now() - started)
                                         .count();
    return RAC_SUCCESS;
}

void ONNXVocoderProvider::cleanup() {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->session.reset();
}

bool ONNXVocoderProvider::is_ready() const {
    std::lock_guard<std::mutex> lock(impl_->mutex);
    return impl_->session != nullptr;
}

}  // namespace runanywhere::vocoder

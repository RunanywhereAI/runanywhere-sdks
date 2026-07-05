#include "catalog/catalog.h"

#include <cstring>

#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "io/output.h"
#include "io/proto.h"

namespace rcli::catalog {

namespace {

namespace v1 = runanywhere::v1;

// VLM pairs / multi-file artifacts. Filenames are the URL basenames so the
// llamacpp loader finds the mmproj companion next to the primary gguf.
constexpr CatalogFile kSmolVlm2Files[] = {
    {"https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/"
     "resolve/main/"
     "SmolVLM2-256M-Video-Instruct-Q8_0.gguf",
     "SmolVLM2-256M-Video-Instruct-Q8_0.gguf", true},
    {"https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/"
     "resolve/main/"
     "mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf",
     "mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf", true},
};

constexpr CatalogFile kLfm2VlFiles[] = {
    {"https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/"
     "LFM2-VL-450M-Q8_0.gguf",
     "LFM2-VL-450M-Q8_0.gguf", true},
    {"https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/"
     "mmproj-LFM2-VL-450M-Q8_0.gguf",
     "mmproj-LFM2-VL-450M-Q8_0.gguf", true},
};

constexpr CatalogFile kQwen2VlFiles[] = {
    {"https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/"
     "Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
     "Qwen2-VL-2B-Instruct-Q4_K_M.gguf", true},
    {"https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/"
     "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
     "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf", true},
};

constexpr CatalogFile kMiniLmFiles[] = {
    {"https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/"
     "model.onnx",
     "model.onnx", true},
    {"https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt",
     "vocab.txt", true},
};

constexpr int64_t MB = 1024LL * 1024LL;

// ids/URLs verbatim from: examples/ios ModelCatalogBootstrap.swift, Android
// ModelCatalog.kt, web model-catalog.ts and
// scripts/tests/download-test-models.sh (qwen3-0.6b Q8_0 matches the Linux test
// rig's LlamaCpp/qwen3-0.6b layout).
constexpr CatalogEntry kCatalog[] = {
    // --- LLM (LlamaCpp / GGUF) ---
    {"qwen3-0.6b", "qwen3", "Qwen3 0.6B Q8_0", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/"
     "Qwen3-0.6B-Q8_0.gguf",
     nullptr, 0, 639 * MB, 4096, true},
    {"qwen3-1.7b-q4_k_m", "qwen3-1.7b", "Qwen3 1.7B Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/"
     "Qwen3-1.7B-Q4_K_M.gguf",
     nullptr, 0, 1230 * MB, 4096, true},
    {"qwen3-4b-q4_k_m", "qwen3-4b", "Qwen3 4B Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/"
     "Qwen3-4B-Q4_K_M.gguf",
     nullptr, 0, 2560 * MB, 4096, true},
    {"llama-3.2-3b", "llama3.2", "Llama 3.2 3B Instruct Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/"
     "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
     nullptr, 0, 2020 * MB, 0, false},
    {"lfm2-350m-q8_0", "lfm2", "LiquidAI LFM2 350M Q8_0",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/"
     "LFM2-350M-Q8_0.gguf",
     nullptr, 0, 400 * MB, 2048, false},
    {"smollm2-360m-q8_0", "smollm2", "SmolLM2 360M Q8_0",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/"
     "SmolLM2-360M.Q8_0.gguf",
     nullptr, 0, 386 * MB, 2048, false},

    // --- VLM (gguf + mmproj pairs) ---
    {"smolvlm2-256m-video-instruct-q8_0", "smolvlm2",
     "SmolVLM2 256M Video Instruct Q8_0", v1::MODEL_CATEGORY_MULTIMODAL,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF, nullptr,
     kSmolVlm2Files, 2, 420 * MB, 2048, false},
    {"lfm2-vl-450m-q8_0", "lfm2-vl", "LFM2-VL 450M Q8_0",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kLfm2VlFiles, 2, 600 * MB, 0, false},
    {"qwen2-vl-2b-instruct-q4_k_m", "qwen2-vl", "Qwen2-VL 2B Instruct Q4_K_M",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kQwen2VlFiles, 2, 1800 * MB, 2048, false},

    // --- Speech (Sherpa-ONNX archives; orchestrator extracts in-core) ---
    {"sherpa-onnx-whisper-tiny.en", "whisper-tiny",
     "Whisper Tiny English (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX,
     "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/"
     "runanywhere-models-v1/"
     "sherpa-onnx-whisper-tiny.en.tar.gz",
     nullptr, 0, 75 * MB, 0, false},
    {"vits-piper-en_US-lessac-medium", "piper",
     "Piper TTS US English (Lessac Medium)",
     v1::MODEL_CATEGORY_SPEECH_SYNTHESIS, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX,
     "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/"
     "runanywhere-models-v1/"
     "vits-piper-en_US-lessac-medium.tar.gz",
     nullptr, 0, 65 * MB, 0, false},

    // --- VAD ---
    // Exact artifact size (matches iOS ModelCatalogBootstrap.swift): the
    // post-finalize size guard treats download_size_bytes as authoritative,
    // and an over-stated 3 MB estimate tripped it on the valid ~2.3 MB file.
    {"silero-vad", "silero", "Silero VAD",
     v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION, v1::INFERENCE_FRAMEWORK_ONNX,
     v1::MODEL_FORMAT_ONNX,
     "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/"
     "silero_vad.onnx",
     nullptr, 0, 2327524, 0, false},

    // --- Embeddings ---
    {"all-minilm-l6-v2", "minilm", "All-MiniLM-L6-v2 (Embeddings)",
     v1::MODEL_CATEGORY_EMBEDDING, v1::INFERENCE_FRAMEWORK_ONNX,
     v1::MODEL_FORMAT_ONNX, nullptr, kMiniLmFiles, 2, 90 * MB, 0, false},
};

constexpr size_t kCatalogCount = sizeof(kCatalog) / sizeof(kCatalog[0]);

rac_result_t register_entry(const CatalogEntry &entry) {
  rac_proto_buffer_t out;
  rac_proto_buffer_init(&out);
  rac_result_t rc = RAC_SUCCESS;

  if (entry.files != nullptr) {
    runanywhere::v1::RegisterMultiFileModelRequest request;
    request.set_id(entry.id);
    request.set_name(entry.name);
    request.set_framework(entry.framework);
    request.set_category(entry.category);
    request.set_format(entry.format);
    request.set_download_size_bytes(entry.download_size_bytes);
    if (entry.context_length > 0) {
      request.set_context_length(entry.context_length);
    }
    if (entry.supports_thinking) {
      request.set_supports_thinking(true);
    }
    for (size_t i = 0; i < entry.file_count; ++i) {
      runanywhere::v1::ModelFileDescriptor *file = request.add_files();
      file->set_url(entry.files[i].url);
      file->set_filename(entry.files[i].filename);
      file->set_is_required(entry.files[i].required);
    }
    const std::string bytes = proto::serialize(request);
    rc = rac_register_multi_file_model_proto(
        reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size(), &out);
  } else {
    runanywhere::v1::RegisterModelFromUrlRequest request;
    request.set_url(entry.url);
    request.set_name(entry.name);
    request.set_id(entry.id);
    request.set_framework(entry.framework);
    request.set_category(entry.category);
    request.set_download_size_bytes(entry.download_size_bytes);
    if (entry.context_length > 0) {
      request.set_context_length(entry.context_length);
    }
    if (entry.supports_thinking) {
      request.set_supports_thinking(true);
    }
    const std::string bytes = proto::serialize(request);
    rc = rac_register_model_from_url_proto(
        reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size(), &out);
  }

  // The saved ModelInfo bytes are not needed here — only the status envelope.
  const rac_result_t status = (rc == RAC_SUCCESS) ? out.status : rc;
  rac_proto_buffer_free(&out);
  return status;
}

} // namespace

const CatalogEntry *all(size_t *count) {
  if (count) {
    *count = kCatalogCount;
  }
  return kCatalog;
}

const CatalogEntry *find(const std::string &id_or_alias) {
  for (const CatalogEntry &entry : kCatalog) {
    if (id_or_alias == entry.id ||
        (entry.alias && id_or_alias == entry.alias)) {
      return &entry;
    }
  }
  return nullptr;
}

std::vector<std::string> suggestions(const std::string &input, size_t max) {
  std::vector<std::string> matches;
  for (const CatalogEntry &entry : kCatalog) {
    if (matches.size() >= max) {
      break;
    }
    if (std::string(entry.id).find(input) != std::string::npos ||
        (entry.alias &&
         std::string(entry.alias).find(input) != std::string::npos)) {
      matches.emplace_back(entry.id);
    }
  }
  return matches;
}

rac_result_t register_all() {
  rac_result_t first_error = RAC_SUCCESS;
  for (const CatalogEntry &entry : kCatalog) {
    const rac_result_t rc = register_entry(entry);
    if (rc != RAC_SUCCESS) {
      out::status_line(
          std::string("warning: catalog registration failed for ") + entry.id +
          ": " + out::describe_result(rc));
      if (first_error == RAC_SUCCESS) {
        first_error = rc;
      }
    }
  }
  return first_error;
}

} // namespace rcli::catalog

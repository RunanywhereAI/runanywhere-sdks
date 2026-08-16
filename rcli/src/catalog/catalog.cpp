#include "catalog/catalog.h"

#include <cstring>

#include "rac/core/rac_core.h"
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

// LiquidAI's own GGUF export. general.architecture is "lfm2" (same as the
// LFM2-VL 450M row above) and the mmproj is a standard clip/mmproj projector,
// verified by reading both GGUF headers off HF.
constexpr CatalogFile kLfm2_5Vl3BFiles[] = {
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-GGUF/resolve/main/"
     "LFM2.5-VL-3B-Q4_K_M.gguf",
     "LFM2.5-VL-3B-Q4_K_M.gguf", true, 1674454240LL},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-GGUF/resolve/main/"
     "mmproj-LFM2.5-VL-3B-Q8_0.gguf",
     "mmproj-LFM2.5-VL-3B-Q8_0.gguf", true, 583109120LL},
};

constexpr CatalogFile kQwen2VlFiles[] = {
    {"https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/"
     "Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
     "Qwen2-VL-2B-Instruct-Q4_K_M.gguf", true},
    {"https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/"
     "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
     "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf", true},
};

constexpr CatalogFile kFara15GgufFiles[] = {
    {"https://huggingface.co/runanywhere/Fara1.5-4B-GGUF/resolve/main/"
     "Fara1.5-4B-Q4_K_M.gguf",
     "Fara1.5-4B-Q4_K_M.gguf", true},
    {"https://huggingface.co/runanywhere/Fara1.5-4B-GGUF/resolve/main/"
     "mmproj-Fara1.5-4B-f16.gguf",
     "mmproj-Fara1.5-4B-f16.gguf", true},
};

constexpr CatalogFile kMiniLmFiles[] = {
    {"https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/"
     "model.onnx",
     "model.onnx", true},
    {"https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt",
     "vocab.txt", true},
};

constexpr CatalogFile kSherpaParakeetTdtV2Files[] = {
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/"
     "1ab9323565ddb038682214b292f588070a538ce2/encoder.int8.onnx",
     "encoder.int8.onnx", true, 652184296LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/"
     "1ab9323565ddb038682214b292f588070a538ce2/decoder.int8.onnx",
     "decoder.int8.onnx", true, 7257753LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/"
     "1ab9323565ddb038682214b292f588070a538ce2/joiner.int8.onnx",
     "joiner.int8.onnx", true, 1739080LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/"
     "1ab9323565ddb038682214b292f588070a538ce2/tokens.txt",
     "tokens.txt", true, 9384LL},
};

constexpr CatalogFile kSherpaParakeetTdtV3Files[] = {
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/"
     "2bda32ec70b097a55adaa07d9a7173915b43cc78/encoder.int8.onnx",
     "encoder.int8.onnx", true, 652184281LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/"
     "2bda32ec70b097a55adaa07d9a7173915b43cc78/decoder.int8.onnx",
     "decoder.int8.onnx", true, 11845275LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/"
     "2bda32ec70b097a55adaa07d9a7173915b43cc78/joiner.int8.onnx",
     "joiner.int8.onnx", true, 6355277LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/"
     "2bda32ec70b097a55adaa07d9a7173915b43cc78/tokens.txt",
     "tokens.txt", true, 93939LL},
};

constexpr CatalogFile kSherpaCanary180MFiles[] = {
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8/resolve/"
     "9077164e0d3dd1d5353743e89ceaa1d3a770838c/encoder.int8.onnx",
     "encoder.int8.onnx", true, 132678643LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8/resolve/"
     "9077164e0d3dd1d5353743e89ceaa1d3a770838c/decoder.int8.onnx",
     "decoder.int8.onnx", true, 74437848LL},
    {"https://huggingface.co/csukuangfj/"
     "sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8/resolve/"
     "9077164e0d3dd1d5353743e89ceaa1d3a770838c/tokens.txt",
     "tokens.txt", true, 53555LL},
};

// Sherpa 1.13.5 is required for the corrected NeMo streaming-transducer
// decoder. Keep every URL on the immutable HF revision and verify each large
// artifact independently so a mutable model update cannot enter a release.
constexpr CatalogFile kSherpaNemotronStreamingAsrFiles[] = {
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-320ms-int8-2026-06-11/"
     "resolve/424ce58898995b713f84341f2e1492f9207a26aa/encoder.int8.onnx",
     "encoder.int8.onnx", true, 657601518LL,
     "f79c3fcc149f268b54b7d5754bdc2ba5c47c16b1fc70d15728a56f6efbf60ca5"},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-320ms-int8-2026-06-11/"
     "resolve/424ce58898995b713f84341f2e1492f9207a26aa/decoder.int8.onnx",
     "decoder.int8.onnx", true, 14978075LL,
     "19f9c98fc6d0a2c33a65a43b36fdb2e914c26c0aa9764be3aebc502a1e982fb0"},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-320ms-int8-2026-06-11/"
     "resolve/424ce58898995b713f84341f2e1492f9207a26aa/joiner.int8.onnx",
     "joiner.int8.onnx", true, 9504438LL,
     "4101c7c679a0bc30483794b27a059e34e79232aa2068d78d51231a22c8b0d7ce"},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-320ms-int8-2026-06-11/"
     "resolve/424ce58898995b713f84341f2e1492f9207a26aa/tokens.txt",
     "tokens.txt", true, 131440LL,
     "729cc103155bafa785f9cd45746cd41cabe97eab7182fc04d594129587958f8a"},
};

// The upstream OpenVoiceOS export omits three metadata_props entries Sherpa
// requires, so it cannot be loaded as published. This repo is that export with
// the entries added; provenance and a reproduction script live in its model
// card.
constexpr CatalogFile kSherpaParakeetCtcFiles[] = {
    {"https://huggingface.co/runanywhere/"
     "sherpa-onnx-nemo-parakeet-ctc-1.1b-int8/resolve/"
     "48a549f552774db3cd09dd1548f3d1a2b37bc7c5/model.int8.onnx",
     "model.int8.onnx", true, 1110014145LL,
     "62f73c17a5301c048c7273cf24ef1cd0c3621d3625c5415fbafe5633d7bf2f98"},
    {"https://huggingface.co/runanywhere/"
     "sherpa-onnx-nemo-parakeet-ctc-1.1b-int8/resolve/"
     "48a549f552774db3cd09dd1548f3d1a2b37bc7c5/tokens.txt",
     "tokens.txt", true, 10374LL,
     "ed16e1a4e3a3aa379138c0b1888e5d49f993c9d512b2be4d46e90a87afd54921"},
};

constexpr CatalogFile kMlxQwen3_06BFiles[] = {
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "added_tokens.json",
     "added_tokens.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "merges.txt",
     "merges.txt", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/"
     "vocab.json",
     "vocab.json", true},
};

constexpr CatalogFile kMlxMaplePreviewFiles[] = {
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/added_tokens.json",
     "added_tokens.json", true, 707LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/chat_template.jinja",
     "chat_template.jinja", true, 3292LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/config.json",
     "config.json", true, 2710LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/merges.txt",
     "merges.txt", true, 1671853LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/"
     "model-00001-of-00003.safetensors",
     "model-00001-of-00003.safetensors", true, 2162084350LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/"
     "model-00002-of-00003.safetensors",
     "model-00002-of-00003.safetensors", true, 2187444586LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/"
     "model-00003-of-00003.safetensors",
     "model-00003-of-00003.safetensors", true, 958711742LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/"
     "model-flashhead.safetensors",
     "model-flashhead.safetensors", true, 6087456LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true, 40054LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/special_tokens_map.json",
     "special_tokens_map.json", true, 613LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/tokenizer.json",
     "tokenizer.json", true, 11422654LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/tokenizer_config.json",
     "tokenizer_config.json", true, 5432LL},
    {"https://huggingface.co/deepgrove/maple-preview-2bit-mlx/resolve/"
     "d0a7314d6bf14c880201b599d7a701cfbc8717e6/vocab.json",
     "vocab.json", true, 2776833LL},
};

constexpr CatalogFile kMlxNemotronNano8BFiles[] = {
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/config.json",
     "config.json", true},
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/bourn23/"
     "nvidia-llama-3.1-nemotron-nano-8b-v1-mlx-4bit/resolve/"
     "00378e66048eadf358aad0f66c09e5c3750f8243/tokenizer_config.json",
     "tokenizer_config.json", true},
};

constexpr CatalogFile kMlxNemotronMini4BFiles[] = {
    {"https://huggingface.co/mlx-community/"
     "Nemotron-Mini-4B-Instruct-4bit-mlx/resolve/"
     "b5784198153d2d71afcc97d4cc38c049abced8cd/chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/"
     "Nemotron-Mini-4B-Instruct-4bit-mlx/resolve/"
     "b5784198153d2d71afcc97d4cc38c049abced8cd/config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/"
     "Nemotron-Mini-4B-Instruct-4bit-mlx/resolve/"
     "b5784198153d2d71afcc97d4cc38c049abced8cd/model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/"
     "Nemotron-Mini-4B-Instruct-4bit-mlx/resolve/"
     "b5784198153d2d71afcc97d4cc38c049abced8cd/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/"
     "Nemotron-Mini-4B-Instruct-4bit-mlx/resolve/"
     "b5784198153d2d71afcc97d4cc38c049abced8cd/tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/"
     "Nemotron-Mini-4B-Instruct-4bit-mlx/resolve/"
     "b5784198153d2d71afcc97d4cc38c049abced8cd/tokenizer_config.json",
     "tokenizer_config.json", true},
};

constexpr CatalogFile kMlxLlama32_1BFiles[] = {
    {"https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/"
     "main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/"
     "main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/"
     "main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/"
     "main/"
     "special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/"
     "main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/"
     "main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

constexpr CatalogFile kMlxQwen2Vl2BFiles[] = {
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "added_tokens.json",
     "added_tokens.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "chat_template.json",
     "chat_template.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "merges.txt",
     "merges.txt", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "preprocessor_config.json",
     "preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/"
     "main/"
     "vocab.json",
     "vocab.json", true},
};

constexpr CatalogFile kMlxFastVlm05BFiles[] = {
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "added_tokens.json",
     "added_tokens.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "llava_qwen.py",
     "llava_qwen.py", false},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "merges.txt",
     "merges.txt", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "preprocessor_config.json",
     "preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "processing_fastvlm.py",
     "processing_fastvlm.py", false},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/"
     "vocab.json",
     "vocab.json", true},
};

// LiquidAI's own MLX 4-bit export. config.json model_type is "lfm2_vl", which
// the pinned mlx-swift-lm 3.31.5 registers in VLMModelFactory (together with
// the "Lfm2VlProcessor" processor class this repo declares). It ships no
// merges.txt/vocab.json — tokenizer.json is the self-contained fast-tokenizer
// format — and its processor lives in processor_config.json rather than
// preprocessor_config.json, which the factory also accepts. Verified via the HF
// API file listing this session; do not add filenames that are not below.
constexpr CatalogFile kMlxLfm2_5Vl3BFiles[] = {
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/LiquidAI/LFM2.5-VL-3B-MLX-4bit/resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

constexpr CatalogFile kMlxQwen3Embedding06BFiles[] = {
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "added_tokens.json",
     "added_tokens.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "merges.txt",
     "merges.txt", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/"
     "resolve/main/"
     "vocab.json",
     "vocab.json", true},
};

constexpr CatalogFile kMlxQwen3Asr06BFiles[] = {
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "chat_template.json",
     "chat_template.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "merges.txt",
     "merges.txt", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "preprocessor_config.json",
     "preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/"
     "vocab.json",
     "vocab.json", true},
};

constexpr CatalogFile kMlxGlmAsrNano2512Files[] = {
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "configuration_glmasr.py",
     "configuration_glmasr.py", false},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "inference.py",
     "inference.py", false},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "modeling_audio.py",
     "modeling_audio.py", false},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "modeling_glmasr.py",
     "modeling_glmasr.py", false},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

constexpr CatalogFile kMlxParakeetCtc11BFiles[] = {
    {"https://huggingface.co/mlx-community/parakeet-ctc-1.1b/resolve/"
     "295d0c0557aef0c445db79b3d09c9a94a69ffeaf/config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/parakeet-ctc-1.1b/resolve/"
     "295d0c0557aef0c445db79b3d09c9a94a69ffeaf/model.safetensors",
     "model.safetensors", true},
};

constexpr CatalogFile kMlxParakeetTdtV2Files[] = {
    {"https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v2/resolve/"
     "8ae155301e23d820d82aa60d24817c900e69e487/config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v2/resolve/"
     "8ae155301e23d820d82aa60d24817c900e69e487/model.safetensors",
     "model.safetensors", true},
};

constexpr CatalogFile kMlxParakeetTdtV3Files[] = {
    {"https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3/resolve/"
     "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15/config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3/resolve/"
     "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15/model.safetensors",
     "model.safetensors", true},
};

constexpr CatalogFile kMlxParakeetRnnt11BFiles[] = {
    {"https://huggingface.co/mlx-community/parakeet-rnnt-1.1b/resolve/"
     "7f399a0d3442123deae9194e71f5c984b2879efa/config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/parakeet-rnnt-1.1b/resolve/"
     "7f399a0d3442123deae9194e71f5c984b2879efa/model.safetensors",
     "model.safetensors", true},
};

constexpr CatalogFile kMlxNemotronStreamingAsrFiles[] = {
    {"https://huggingface.co/mlx-community/"
     "nemotron-3.5-asr-streaming-0.6b-8bit/resolve/"
     "7279359e4481b5e9e185a318bd618e429c6d86cd/config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/"
     "nemotron-3.5-asr-streaming-0.6b-8bit/resolve/"
     "7279359e4481b5e9e185a318bd618e429c6d86cd/model.safetensors",
     "model.safetensors", true},
};

constexpr CatalogFile kMlxQwen3Tts06BBaseFiles[] = {
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "merges.txt",
     "merges.txt", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "preprocessor_config.json",
     "preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "speech_tokenizer/config.json",
     "speech_tokenizer/config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "speech_tokenizer/configuration.json",
     "speech_tokenizer/configuration.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "speech_tokenizer/model.safetensors",
     "speech_tokenizer/model.safetensors", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "speech_tokenizer/preprocessor_config.json",
     "speech_tokenizer/preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/"
     "resolve/main/"
     "vocab.json",
     "vocab.json", true},
};

constexpr CatalogFile kMlxSoprano1180M5BitFiles[] = {
    {"https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/"
     "special_tokens_map.json",
     "special_tokens_map.json", true},
    {"https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// PrismML Bonsai-27B 1-bit MLX (qwen3_5). Files match the HF repo siblings
// needed for mlx-swift-lm load (weights + tokenizer + config). Vision
// preprocessor stubs are present on HF but not required for text-only LLM use.
constexpr CatalogFile kMlxBonsai27B1BitFiles[] = {
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "merges.txt",
     "merges.txt", true},
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "model.safetensors",
     "model.safetensors", true},
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit/resolve/main/"
     "vocab.json",
     "vocab.json", true},
};

// PrismML Bonsai 1-bit MLX at 1.7B/4B/8B — same 8-file set as the 27B above
// (mlx-swift-lm needs weights + tokenizer + config; vision preprocessor stubs
// on some repos are not required for text-only LLM use).
#define BONSAI_MLX_FILES(repo)                                                 \
  {"https://huggingface.co/prism-ml/" repo                                     \
   "/resolve/main/chat_template.jinja",                                        \
   "chat_template.jinja", true},                                               \
      {"https://huggingface.co/prism-ml/" repo "/resolve/main/config.json",    \
       "config.json", true},                                                   \
      {"https://huggingface.co/prism-ml/" repo "/resolve/main/merges.txt",     \
       "merges.txt", true},                                                    \
      {"https://huggingface.co/prism-ml/" repo                                 \
       "/resolve/main/model.safetensors",                                      \
       "model.safetensors", true},                                             \
      {"https://huggingface.co/prism-ml/" repo                                 \
       "/resolve/main/model.safetensors.index.json",                           \
       "model.safetensors.index.json", true},                                  \
      {"https://huggingface.co/prism-ml/" repo "/resolve/main/tokenizer.json", \
       "tokenizer.json", true},                                                \
      {"https://huggingface.co/prism-ml/" repo                                 \
       "/resolve/main/tokenizer_config.json",                                  \
       "tokenizer_config.json", true},                                         \
      {"https://huggingface.co/prism-ml/" repo "/resolve/main/vocab.json",     \
       "vocab.json", true},

constexpr CatalogFile kMlxBonsai1_7B1BitFiles[] = {
    BONSAI_MLX_FILES("Bonsai-1.7B-mlx-1bit")};
constexpr CatalogFile kMlxBonsai4B1BitFiles[] = {
    BONSAI_MLX_FILES("Bonsai-4B-mlx-1bit")};
constexpr CatalogFile kMlxBonsai8B1BitFiles[] = {
    BONSAI_MLX_FILES("Bonsai-8B-mlx-1bit")};

// PrismML Ternary-Bonsai 2-bit MLX at 1.7B/4B/8B — these repos do NOT ship
// merges.txt/vocab.json (tokenizer.json is the self-contained fast-tokenizer
// format here), unlike the plain-Bonsai repos above. Verified via HF API file
// listing this session — do not add those two filenames or the download 404s.
#define TERNARY_BONSAI_MLX_FILES_SMALL(repo)                                   \
  {"https://huggingface.co/prism-ml/" repo                                     \
   "/resolve/main/chat_template.jinja",                                        \
   "chat_template.jinja", true},                                               \
      {"https://huggingface.co/prism-ml/" repo "/resolve/main/config.json",    \
       "config.json", true},                                                   \
      {"https://huggingface.co/prism-ml/" repo                                 \
       "/resolve/main/model.safetensors",                                      \
       "model.safetensors", true},                                             \
      {"https://huggingface.co/prism-ml/" repo                                 \
       "/resolve/main/model.safetensors.index.json",                           \
       "model.safetensors.index.json", true},                                  \
      {"https://huggingface.co/prism-ml/" repo "/resolve/main/tokenizer.json", \
       "tokenizer.json", true},                                                \
      {"https://huggingface.co/prism-ml/" repo                                 \
       "/resolve/main/tokenizer_config.json",                                  \
       "tokenizer_config.json", true},

constexpr CatalogFile kMlxTernaryBonsai1_7B2BitFiles[] = {
    TERNARY_BONSAI_MLX_FILES_SMALL("Ternary-Bonsai-1.7B-mlx-2bit")};
constexpr CatalogFile kMlxTernaryBonsai4B2BitFiles[] = {
    TERNARY_BONSAI_MLX_FILES_SMALL("Ternary-Bonsai-4B-mlx-2bit")};
constexpr CatalogFile kMlxTernaryBonsai8B2BitFiles[] = {
    TERNARY_BONSAI_MLX_FILES_SMALL("Ternary-Bonsai-8B-mlx-2bit")};

// Ternary-Bonsai-27B-mlx-2bit DOES ship merges.txt/vocab.json (matches the
// plain-Bonsai 8-file pattern) — verified via HF API file listing this
// session; the smaller Ternary sizes above do not.
constexpr CatalogFile kMlxTernaryBonsai27B2BitFiles[] = {
    BONSAI_MLX_FILES("Ternary-Bonsai-27B-mlx-2bit")};

#undef BONSAI_MLX_FILES
#undef TERNARY_BONSAI_MLX_FILES_SMALL

// Meta Muse Glimmer 30B GGUF + mmproj (image-text-to-text; llama.cpp mmproj is
// image-only, so this is vision-capable, not the checkpoint's full "omni"
// audio/video marketing claim). Sizes verified via HF API blobs this session.
constexpr CatalogFile kMuseGlimmer30BFiles[] = {
    {"https://huggingface.co/unsloth/Muse-Glimmer-30B-GGUF/resolve/"
     "faa5b025c584459c13febfa5c59883516710ae39/"
     "Muse-Glimmer-30B-UD-Q4_K_XL.gguf",
     "Muse-Glimmer-30B-UD-Q4_K_XL.gguf", true, 15878222368LL},
    {"https://huggingface.co/unsloth/Muse-Glimmer-30B-GGUF/resolve/"
     "faa5b025c584459c13febfa5c59883516710ae39/"
     "mmproj-Muse-Glimmer-30B-Q8_0.gguf",
     "mmproj-Muse-Glimmer-30B-Q8_0.gguf", true, 2051685088LL},
};

// NVIDIA Nemotron-3-Nano-Omni-30B-A3B-Reasoning GGUF + mmproj. Same
// image-only mmproj caveat as Muse Glimmer above: this is vision-capable via
// llama.cpp, not the model's full audio/video "omni" surface.
constexpr CatalogFile kNemotronOmniReasoningFiles[] = {
    {"https://huggingface.co/unsloth/"
     "NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF/resolve/"
     "571758804835f56154718683f5c0e388b7d0fef9/"
     "NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-UD-Q4_K_M.gguf",
     "NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-UD-Q4_K_M.gguf", true,
     23887023552LL},
    {"https://huggingface.co/unsloth/"
     "NVIDIA-Nemotron-3-Nano-Omni-30B-A3B-Reasoning-GGUF/resolve/"
     "571758804835f56154718683f5c0e388b7d0fef9/"
     "mmproj-F16.gguf",
     "mmproj-F16.gguf", true, 1587540224LL},
};

// mlx-community/gemma-4-e2b-it-4bit — config.json model_type "gemma4",
// registered in the pinned mlx-swift-lm 3.31.5 LLMTypeRegistry/VLMTypeRegistry
// alike. File list + sizes verified via HF API blobs this session.
constexpr CatalogFile kMlxGemma4E2BFiles[] = {
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "model.safetensors",
     "model.safetensors", true, 3550670554LL},
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit/resolve/"
     "238767527555cb75a05732a84dff5d6ba0dd6809/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// mlx-community/gemma-4-E4B-it-qat-4bit — model_type "gemma4" (registered).
constexpr CatalogFile kMlxGemma4E4BFiles[] = {
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "model-00001-of-00002.safetensors",
     "model-00001-of-00002.safetensors", true, 4249502053LL},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "model-00002-of-00002.safetensors",
     "model-00002-of-00002.safetensors", true, 2548805689LL},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-E4B-it-qat-4bit/resolve/"
     "0f35c6f6d386f7f74e628bd7c6526ce531212300/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// mlx-community/gemma-4-12B-it-qat-4bit — model_type "gemma4_unified"
// (registered in both LLMTypeRegistry and VLMTypeRegistry).
constexpr CatalogFile kMlxGemma4_12BFiles[] = {
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "model-00001-of-00003.safetensors",
     "model-00001-of-00003.safetensors", true, 5343482357LL},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "model-00002-of-00003.safetensors",
     "model-00002-of-00003.safetensors", true, 5315166254LL},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "model-00003-of-00003.safetensors",
     "model-00003-of-00003.safetensors", true, 329123819LL},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-12B-it-qat-4bit/resolve/"
     "e70c6b3ba0979b3357dcd2f223ad8bde7787a6b6/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// mlx-community/gemma-4-26b-a4b-it-4bit (MoE) — model_type "gemma4"
// (registered).
constexpr CatalogFile kMlxGemma4_26BA4BFiles[] = {
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "model-00001-of-00003.safetensors",
     "model-00001-of-00003.safetensors", true, 5320218487LL},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "model-00002-of-00003.safetensors",
     "model-00002-of-00003.safetensors", true, 5363328422LL},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "model-00003-of-00003.safetensors",
     "model-00003-of-00003.safetensors", true, 4657658867LL},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit/resolve/"
     "0d77464eeb233a2da68ebf9d7dc4edaac7db956d/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// mlx-community/gemma-4-31b-it-4bit — the plain 4bit variant, NOT
// "-qat-4bit" (that name 404s / does not exist as a clean repo; verified this
// session). model_type "gemma4" (registered).
constexpr CatalogFile kMlxGemma4_31BFiles[] = {
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "model-00001-of-00004.safetensors",
     "model-00001-of-00004.safetensors", true, 5366617512LL},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "model-00002-of-00004.safetensors",
     "model-00002-of-00004.safetensors", true, 5361642573LL},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "model-00003-of-00004.safetensors",
     "model-00003-of-00004.safetensors", true, 5367276094LL},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "model-00004-of-00004.safetensors",
     "model-00004-of-00004.safetensors", true, 2316480497LL},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/gemma-4-31b-it-4bit/resolve/"
     "696d436c404745a59f30e4939a658162b0a9e57f/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// mlx-community/Qwen3.6-35B-A3B-4bit (MoE) — config.json model_type
// "qwen3_5_moe", registered in mlx-swift-lm 3.31.5's LLMTypeRegistry.
constexpr CatalogFile kMlxQwen3_6_35BA3BFiles[] = {
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "configuration.json",
     "configuration.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "model-00001-of-00004.safetensors",
     "model-00001-of-00004.safetensors", true, 5288196018LL},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "model-00002-of-00004.safetensors",
     "model-00002-of-00004.safetensors", true, 5368472749LL},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "model-00003-of-00004.safetensors",
     "model-00003-of-00004.safetensors", true, 5368324139LL},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "model-00004-of-00004.safetensors",
     "model-00004-of-00004.safetensors", true, 4377211365LL},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "preprocessor_config.json",
     "preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "video_preprocessor_config.json",
     "video_preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.6-35B-A3B-4bit/resolve/"
     "38740b847e4cb78f352aba30aa41c76e08e6eb46/"
     "vocab.json",
     "vocab.json", true},
};

// mlx-community/Qwen3.8-27B-4bit (dense) — config.json model_type "qwen3_5",
// registered in mlx-swift-lm 3.31.5's LLMTypeRegistry.
constexpr CatalogFile kMlxQwen3_8_27BFiles[] = {
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "model-00001-of-00003.safetensors",
     "model-00001-of-00003.safetensors", true, 5343268662LL},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "model-00002-of-00003.safetensors",
     "model-00002-of-00003.safetensors", true, 5354185130LL},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "model-00003-of-00003.safetensors",
     "model-00003-of-00003.safetensors", true, 5357087557LL},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "preprocessor_config.json",
     "preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "processor_config.json",
     "processor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "video_preprocessor_config.json",
     "video_preprocessor_config.json", true},
    {"https://huggingface.co/mlx-community/Qwen3.8-27B-4bit/resolve/"
     "3e6447f082e89cc7f0bc6e5441afd38dfce760ff/"
     "vocab.json",
     "vocab.json", true},
};

// IBM Granite 4.1 MLX — config.json model_type "granite" (registered in
// mlx-swift-lm 3.31.5's LLMTypeRegistry). File set verified via HF API.
constexpr CatalogFile kMlxGranite4_1_3BFiles[] = {
    {"https://huggingface.co/mlx-community/granite-4.1-3b-4bit/resolve/"
     "b1b476b5a17c46b7d6cd663b4a8ed44b66720aef/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/granite-4.1-3b-4bit/resolve/"
     "b1b476b5a17c46b7d6cd663b4a8ed44b66720aef/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-3b-4bit/resolve/"
     "b1b476b5a17c46b7d6cd663b4a8ed44b66720aef/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-3b-4bit/resolve/"
     "b1b476b5a17c46b7d6cd663b4a8ed44b66720aef/"
     "model.safetensors",
     "model.safetensors", true, 2127162429LL},
    {"https://huggingface.co/mlx-community/granite-4.1-3b-4bit/resolve/"
     "b1b476b5a17c46b7d6cd663b4a8ed44b66720aef/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-3b-4bit/resolve/"
     "b1b476b5a17c46b7d6cd663b4a8ed44b66720aef/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-3b-4bit/resolve/"
     "b1b476b5a17c46b7d6cd663b4a8ed44b66720aef/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// mlx-community/granite-4.1-8b-4bit — NOT in the original ask (which assumed
// no clean official MLX 8B quant existed), but a real, official mlx-community
// repo does exist: Apache-2.0, base_model ibm-granite/granite-4.1-8b,
// model_type "granite" (registered). Verified via HF API this session; added
// for parity with the 3B/30B MLX rows below.
constexpr CatalogFile kMlxGranite4_1_8BFiles[] = {
    {"https://huggingface.co/mlx-community/granite-4.1-8b-4bit/resolve/"
     "08fb1e272f7bd49fa83ce279bbdc496c980380ac/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/granite-4.1-8b-4bit/resolve/"
     "08fb1e272f7bd49fa83ce279bbdc496c980380ac/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-8b-4bit/resolve/"
     "08fb1e272f7bd49fa83ce279bbdc496c980380ac/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-8b-4bit/resolve/"
     "08fb1e272f7bd49fa83ce279bbdc496c980380ac/"
     "model.safetensors",
     "model.safetensors", true, 5238406779LL},
    {"https://huggingface.co/mlx-community/granite-4.1-8b-4bit/resolve/"
     "08fb1e272f7bd49fa83ce279bbdc496c980380ac/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-8b-4bit/resolve/"
     "08fb1e272f7bd49fa83ce279bbdc496c980380ac/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-8b-4bit/resolve/"
     "08fb1e272f7bd49fa83ce279bbdc496c980380ac/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

constexpr CatalogFile kMlxGranite4_1_30BFiles[] = {
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "chat_template.jinja",
     "chat_template.jinja", true},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "config.json",
     "config.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "generation_config.json",
     "generation_config.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "model-00001-of-00004.safetensors",
     "model-00001-of-00004.safetensors", true, 5360664833LL},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "model-00002-of-00004.safetensors",
     "model-00002-of-00004.safetensors", true, 5363828231LL},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "model-00003-of-00004.safetensors",
     "model-00003-of-00004.safetensors", true, 5363828281LL},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "model-00004-of-00004.safetensors",
     "model-00004-of-00004.safetensors", true, 1953655228LL},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "model.safetensors.index.json",
     "model.safetensors.index.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "tokenizer.json",
     "tokenizer.json", true},
    {"https://huggingface.co/mlx-community/granite-4.1-30b-4bit/resolve/"
     "03e8065d3219e525aa27fc4aaa9b375fe2cd6cb8/"
     "tokenizer_config.json",
     "tokenizer_config.json", true},
};

// Supertone Supertonic v3 TTS via Sherpa-ONNX. NOT the raw Supertone/
// supertonic-3 HF repo — its JSON voice styles / unicode indexer do not match
// what sherpa-onnx's OfflineTtsSupertonicModelConfig loader expects (a binary
// voice.bin + unicode_indexer.bin). This is the pre-converted bundle whose
// 7 filenames match that loader's fields 1:1 (see
// sherpa-onnx/csrc/offline-tts-supertonic-model-config.h). MIT license.
// Requires sherpa-onnx >= 1.13.2 (pinned SHERPA_ONNX_VERSION_* in
// core/VERSIONS already satisfies this).
constexpr CatalogFile kSherpaSupertonicV3Files[] = {
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/"
     "cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/"
     "duration_predictor.int8.onnx",
     "duration_predictor.int8.onnx", true, 3700147LL},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/"
     "cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/"
     "text_encoder.int8.onnx",
     "text_encoder.int8.onnx", true, 36416150LL},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/"
     "cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/tts.json",
     "tts.json", true, 8253LL},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/"
     "cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/"
     "unicode_indexer.bin",
     "unicode_indexer.bin", true, 262144LL},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/"
     "cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/"
     "vector_estimator.int8.onnx",
     "vector_estimator.int8.onnx", true, 78400833LL},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/"
     "cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/"
     "vocoder.int8.onnx",
     "vocoder.int8.onnx", true, 25991073LL},
    {"https://huggingface.co/csukuangfj2/"
     "sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/"
     "cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/voice.bin",
     "voice.bin", true, 517168LL},
};

constexpr int64_t MB = 1024LL * 1024LL;

// ids/URLs verbatim from the consumer apps (RunanywhereAI/runanywhere-{ios,
// android,web}: ModelCatalogBootstrap.swift, ModelCatalog.kt, model-catalog.ts)
// and tests/scripts/download-test-models.sh (qwen3-0.6b Q8_0 matches the Linux
// test rig's LlamaCpp/qwen3-0.6b layout).
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
    // RunAnywhere's canonical-based llama.cpp fork supports PrismML's Q1_0
    // Bonsai artifacts. Ternary-Bonsai uses the explicitly canonical
    // Q2_0_g64 artifacts below; legacy 128-value Q2_0 remains unsupported.
    // Exact artifact byte sizes.
    {"bonsai-1.7b-q1_0", "bonsai-1.7b", "Bonsai-1.7B 1-bit Q1_0 (CPU)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/"
     "Bonsai-1.7B-Q1_0.gguf",
     nullptr, 0, 248302272LL, 4096, true},
    {"bonsai-4b-q1_0", "bonsai-4b", "Bonsai-4B 1-bit Q1_0 (CPU)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prism-ml/Bonsai-4B-gguf/resolve/main/"
     "Bonsai-4B-Q1_0.gguf",
     nullptr, 0, 572270624LL, 4096, true},
    {"bonsai-8b-q1_0", "bonsai-8b", "Bonsai-8B 1-bit Q1_0 (CPU)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prism-ml/Bonsai-8B-gguf/resolve/main/"
     "Bonsai-8B-Q1_0.gguf",
     nullptr, 0, 1158654496LL, 4096, true},
    {"bonsai-27b-q1_0", "bonsai-27b", "Bonsai-27B 1-bit Q1_0 (CPU)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/"
     "Bonsai-27B-Q1_0.gguf",
     nullptr, 0, 3803452480LL, 4096, true},
    {"ternary-bonsai-1.7b-q2_0-g64", "ternary-bonsai-1.7b",
     "Ternary-Bonsai-1.7B Q2_0 g64", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf/resolve/"
     "983b5dec2ff16aab79990711ba0f828a499a7e6a/"
     "Ternary-Bonsai-1.7B-Q2_0_g64.gguf",
     nullptr, 0, 490163968LL, 4096, true},
    {"ternary-bonsai-4b-q2_0-g64", "ternary-bonsai-4b",
     "Ternary-Bonsai-4B Q2_0 g64", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prism-ml/Ternary-Bonsai-4B-gguf/resolve/"
     "a3eb42bafe873f9686bc97486c43b72ef7d75ec8/"
     "Ternary-Bonsai-4B-Q2_0_g64.gguf",
     nullptr, 0, 1137806656LL, 4096, true},
    {"ternary-bonsai-8b-q2_0-g64", "ternary-bonsai-8b",
     "Ternary-Bonsai-8B Q2_0 g64", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/prism-ml/Ternary-Bonsai-8B-gguf/resolve/"
     "c2aefbeb4b24469cd11579c3384b990404c17a30/"
     "Ternary-Bonsai-8B-Q2_0_g64.gguf",
     nullptr, 0, 2310125920LL, 4096, true},
    {"maple-preview-tq1_0-q4_k", "maple-preview",
     "DeepGrove Maple Preview TQ1_0 + Q4_K head (CPU)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/deepgrove/maple-preview-GGUF/resolve/"
     "f5466f918e0c50cdb9d4d47a6f35813509a42a30/"
     "maple-preview-TQ1_0-head-Q4_K.gguf",
     nullptr, 0, 4984016416LL, 4096, true},
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

    // Google Gemma 4 family (GGUF). Licensed under Apache 2.0; preserve the
    // upstream license and attribution notices when redistributing.
    {"gemma-4-e2b-it-q4_k_m", "gemma4-e2b", "Gemma 4 E2B IT Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/"
     "0314792d7f1f7e229411f620751375812bb9faf2/"
     "gemma-4-E2B-it-Q4_K_M.gguf",
     nullptr, 0, 3106738272LL, 4096, false},
    {"gemma-4-e4b-it-q4_k_m", "gemma4-e4b", "Gemma 4 E4B IT Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/"
     "bfc15c382204943c3a8fff0c750b94ae2364d7a3/"
     "gemma-4-E4B-it-Q4_K_M.gguf",
     nullptr, 0, 4977171584LL, 4096, false},
    {"gemma-4-12b-it-q4_k_m", "gemma4-12b", "Gemma 4 12B IT Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/"
     "fc034cfff751157913579611efad8462ac1be606/"
     "gemma-4-12b-it-Q4_K_M.gguf",
     nullptr, 0, 7121861440LL, 4096, false},
    {"gemma-4-26b-a4b-it-q4_k_xl", "gemma4-26b-a4b",
     "Gemma 4 26B-A4B IT UD-Q4_K_XL (MoE)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/"
     "c099eb48e663fd284577b04978a94ffccb261841/"
     "gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf",
     nullptr, 0, 17010980576LL, 4096, false},
    {"gemma-4-31b-it-q4_k_m", "gemma4-31b", "Gemma 4 31B IT Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/resolve/"
     "c1ac76e99d5513b141e8adde7288b85c3f9c32ec/"
     "gemma-4-31B-it-Q4_K_M.gguf",
     nullptr, 0, 18323733440LL, 4096, false},
    // Smaller quant of the same 31B model for tighter RAM budgets.
    {"gemma-4-31b-it-ud-q2_k_xl", "gemma4-31b-q2", "Gemma 4 31B IT UD-Q2_K_XL",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/gemma-4-31B-it-GGUF/resolve/"
     "c1ac76e99d5513b141e8adde7288b85c3f9c32ec/"
     "gemma-4-31B-it-UD-Q2_K_XL.gguf",
     nullptr, 0, 11774991296LL, 4096, false},

    // Qwen3.6-35B-A3B (MoE, agentic-coding, Apache 2.0).
    {"qwen3.6-35b-a3b-q4_k_m", "qwen3.6-35b", "Qwen3.6 35B-A3B UD-Q4_K_M (MoE)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/"
     "a483e9e6cbd595906af30beda3187c2663a1118c/"
     "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf",
     nullptr, 0, 22134528992LL, 4096, true},
    // Qwen3.8-27B (dense, newest Qwen, Apache 2.0).
    {"qwen3.8-27b-q4_k_m", "qwen3.8-27b", "Qwen3.8 27B Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/"
     "f1bfb127c64f7072bdd2cad55f258b9c8b2910fe/"
     "Qwen3.8-27B-Q4_K_M.gguf",
     nullptr, 0, 17106775008LL, 4096, true},

    // IBM Granite 4.1 family (Apache 2.0).
    {"granite-4.1-3b-q4_k_m", "granite4.1-3b", "IBM Granite 4.1 3B Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/granite-4.1-3b-GGUF/resolve/"
     "5b88826e4b80789548180f8faab39c5cf68772c9/"
     "granite-4.1-3b-Q4_K_M.gguf",
     nullptr, 0, 2099502400LL, 4096, false},
    {"granite-4.1-8b-q4_k_m", "granite4.1-8b", "IBM Granite 4.1 8B Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/granite-4.1-8b-GGUF/resolve/"
     "6f9671f73eb03273bc09319194b8a4e810e03a8f/"
     "granite-4.1-8b-Q4_K_M.gguf",
     nullptr, 0, 5347915136LL, 4096, false},
    {"granite-4.1-30b-q4_k_m", "granite4.1-30b", "IBM Granite 4.1 30B Q4_K_M",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/unsloth/granite-4.1-30b-GGUF/resolve/"
     "6cb34f31b11ca4c1433de1af7391dac46de4e666/"
     "granite-4.1-30b-Q4_K_M.gguf",
     nullptr, 0, 17490241472LL, 4096, false},

    // --- VLM (gguf + mmproj pairs) ---
    {"smolvlm2-256m-video-instruct-q8_0", "smolvlm2",
     "SmolVLM2 256M Video Instruct Q8_0", v1::MODEL_CATEGORY_MULTIMODAL,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF, nullptr,
     kSmolVlm2Files, 2, 420 * MB, 2048, false},
    {"lfm2-vl-450m-q8_0", "lfm2-vl", "LFM2-VL 450M Q8_0",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kLfm2VlFiles, 2, 600 * MB, 0, false},
    // Native window is 128k (lfm2.context_length in the GGUF); 4096 is the
    // on-device working context, matching the other multi-GB VLM row.
    {"lfm2.5-vl-3b-q4_k_m", "lfm2.5-vl", "LFM2.5-VL 3B Q4_K_M",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kLfm2_5Vl3BFiles, 2, 2257563360LL, 4096,
     false},
    {"qwen2-vl-2b-instruct-q4_k_m", "qwen2-vl", "Qwen2-VL 2B Instruct Q4_K_M",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kQwen2VlFiles, 2, 1800 * MB, 2048, false},
    {"fara1.5-4b-q4_k_m", "fara", "Fara1.5 4B Computer-Use Agent Q4_K_M",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kFara15GgufFiles, 2, 3300 * MB, 4096,
     false,
     /*memory_required_bytes*/ 0, /*cua_profile*/ "fara"},
    // Meta Muse Glimmer 30B (Apache 2.0). llama.cpp's mmproj is image-only —
    // vision-capable, not the checkpoint's marketed audio/video "omni" surface.
    {"muse-glimmer-30b-q4_k_xl", "muse-glimmer", "Muse Glimmer 30B UD-Q4_K_XL",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kMuseGlimmer30BFiles, 2, 17929907456LL,
     4096, false},
    // NVIDIA Nemotron-3-Nano-Omni-30B-A3B-Reasoning (MoE, NVIDIA Open Model
    // License). Same image-only mmproj caveat as Muse Glimmer above.
    {"nemotron-3-nano-omni-30b-a3b-reasoning-q4_k_m", "nemotron-omni",
     "NVIDIA Nemotron-3-Nano-Omni 30B-A3B Reasoning UD-Q4_K_M (vision, MoE)",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_LLAMA_CPP,
     v1::MODEL_FORMAT_GGUF, nullptr, kNemotronOmniReasoningFiles, 2,
     25474563776LL, 4096, true},

    // --- Speech (Sherpa-ONNX archives; orchestrator extracts in-core) ---
    {"sherpa-onnx-whisper-tiny.en", "whisper-tiny",
     "Whisper Tiny English (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX,
     "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/"
     "runanywhere-models-v1/"
     "sherpa-onnx-whisper-tiny.en.tar.gz",
     nullptr, 0, 75 * MB, 0, false},
    {"sherpa-nemo-parakeet-tdt-0.6b-v2-int8", "parakeet-tdt-v2",
     "NVIDIA Parakeet TDT 0.6B v2 INT8 (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX, nullptr, kSherpaParakeetTdtV2Files, 4, 661190513LL,
     0, false},
    {"sherpa-nemo-parakeet-tdt-0.6b-v3-int8", "parakeet-tdt-v3",
     "NVIDIA Parakeet TDT 0.6B v3 INT8 (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX, nullptr, kSherpaParakeetTdtV3Files, 4, 670478772LL,
     0, false},
    {"sherpa-nemo-parakeet-ctc-1.1b-int8", "parakeet-ctc",
     "NVIDIA Parakeet CTC 1.1B INT8 (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX, nullptr, kSherpaParakeetCtcFiles, 2, 1110024519LL,
     0, false, 2147483648LL},
    {"sherpa-nemo-canary-180m-flash-int8", "canary-180m",
     "NVIDIA Canary 180M Flash INT8 (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX, nullptr, kSherpaCanary180MFiles, 3, 207170046LL, 0,
     false},
    {"sherpa-nemotron-3.5-asr-streaming-0.6b-320ms-int8",
     "nemotron-asr-streaming",
     "NVIDIA Nemotron 3.5 Streaming ASR 0.6B 320ms INT8 (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX, nullptr, kSherpaNemotronStreamingAsrFiles, 4,
     682215471LL, 0, false},
    {"vits-piper-en_US-lessac-medium", "piper",
     "Piper TTS US English (Lessac Medium)",
     v1::MODEL_CATEGORY_SPEECH_SYNTHESIS, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX,
     "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/"
     "runanywhere-models-v1/"
     "vits-piper-en_US-lessac-medium.tar.gz",
     nullptr, 0, 65 * MB, 0, false},
    // Supertone Supertonic v3 (MIT). Not the raw Supertone/supertonic-3 repo —
    // see kSherpaSupertonicV3Files for why. Needs sherpa-onnx >= 1.13.2.
    {"sherpa-supertonic-3-tts-int8", "supertonic",
     "Supertone Supertonic v3 TTS INT8 (Sherpa-ONNX)",
     v1::MODEL_CATEGORY_SPEECH_SYNTHESIS, v1::INFERENCE_FRAMEWORK_SHERPA,
     v1::MODEL_FORMAT_ONNX, nullptr, kSherpaSupertonicV3Files, 7, 145295768LL,
     0, false},

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

    // --- Speaker diarization (ONNX Runtime) ---
    {"diar-streaming-sortformer-4spk-v2.1", "sortformer",
     "NVIDIA Streaming Sortformer 4-Speaker v2.1",
     v1::MODEL_CATEGORY_SPEAKER_DIARIZATION, v1::INFERENCE_FRAMEWORK_ONNX,
     v1::MODEL_FORMAT_ONNX,
     "https://huggingface.co/cgus/diar_streaming_sortformer_4spk-v2.1-onnx/"
     "resolve/main/diar_streaming_sortformer_4spk-v2.1.onnx",
     nullptr, 0, 492242946LL, 0, false},

    // --- Semantic segmentation (ONNX Runtime) ---
    {"segformer-b0-ade-512", "segformer",
     "SegFormer B0 ADE20K 512 (Semantic Segmentation)",
     v1::MODEL_CATEGORY_SEMANTIC_SEGMENTATION, v1::INFERENCE_FRAMEWORK_ONNX,
     v1::MODEL_FORMAT_ONNX,
     "https://huggingface.co/Xenova/segformer-b0-finetuned-ade-512-512/"
     "resolve/main/onnx/model.onnx",
     nullptr, 0, 15335446LL, 0, false},

    // --- Embeddings ---
    {"nemotron-3-embed-1b-q4_k_m", "nemotron-3-embed",
     "NVIDIA Nemotron 3 Embed 1B Q4_K_M", v1::MODEL_CATEGORY_EMBEDDING,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/zenmagnets/"
     "Nemotron-3-Embed-1B-Q4_K_M-GGUF/resolve/"
     "06df1fde6f7009c91f6cc3cd520081921929a678/"
     "nemotron-3-embed-1b-q4_k_m.gguf",
     nullptr, 0, 749352096LL, 0, false},
    {"llama-nemotron-embed-1b-v2-q4_k_m", "llama-nemotron-embed",
     "NVIDIA Llama Nemotron Embed 1B v2 Q4_K_M", v1::MODEL_CATEGORY_EMBEDDING,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/mykor/llama-nemotron-embed-1b-v2-GGUF/"
     "resolve/bf7c9832b1d76f86777379e58b7b74805ee58006/"
     "llama-nemotron-embed-1B-v2-Q4_K_M.gguf",
     nullptr, 0, 807690624LL, 0, false},
    // NVIDIA Llama Embed Nemotron 8B — portable GGUF previously HNPU-only.
    {"llama-embed-nemotron-8b-q4_k_m", "llama-embed-nemotron",
     "NVIDIA Llama Embed Nemotron 8B Q4_K_M", v1::MODEL_CATEGORY_EMBEDDING,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/mradermacher/llama-embed-nemotron-8b-GGUF/"
     "resolve/e7ae3cbae4f7693bbd75ec959bf293f39e1f2e25/"
     "llama-embed-nemotron-8b.Q4_K_M.gguf",
     nullptr, 0, 4625233184LL, 0, false},
    {"all-minilm-l6-v2", "minilm", "All-MiniLM-L6-v2 (Embeddings)",
     v1::MODEL_CATEGORY_EMBEDDING, v1::INFERENCE_FRAMEWORK_ONNX,
     v1::MODEL_FORMAT_ONNX, nullptr, kMiniLmFiles, 2, 90 * MB, 0, false},

    // --- Reranking (llama.cpp cross-encoder; `rcli rerank -m <id>`) ---
    {"bge-reranker-v2-m3-q4_k_m", "bge-reranker",
     "BGE Reranker v2-m3 Q4_K_M (Reranking)", v1::MODEL_CATEGORY_EMBEDDING,
     v1::INFERENCE_FRAMEWORK_LLAMA_CPP, v1::MODEL_FORMAT_GGUF,
     "https://huggingface.co/gpustack/bge-reranker-v2-m3-GGUF/resolve/main/"
     "bge-reranker-v2-m3-Q4_K_M.gguf",
     nullptr, 0, 438376864LL, 0, false},

    // --- Image generation (CoreML diffusion; Apple only) ---
    // Apple-optimized Stable Diffusion 1.5. Id matches the built-in diffusion
    // model registry (diffusion_model_registry.cpp) and the Swift facade's
    // canonical `.imageGeneration` model, so `rcli image generate` resolves it
    // and `rcli list` shows it. The palettized CoreML bundle is a directory of
    // compiled .mlmodelc sub-models served by the `coreml` engine; a
    // pre-fetched bundle can also be passed to `--model` as a local path.
    {"stable-diffusion-v1-5-coreml", "sd15", "Stable Diffusion 1.5 (CoreML)",
     v1::MODEL_CATEGORY_IMAGE_GENERATION, v1::INFERENCE_FRAMEWORK_COREML,
     v1::MODEL_FORMAT_MLPACKAGE,
     "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized",
     nullptr, 0, 1200 * MB, 0, false},

    // --- MLX (Apple Silicon / Apple GPU via mlx-swift-lm) ---
    {"mlx-qwen3-0.6b-4bit", "mlx-qwen3", "Qwen3 0.6B 4-bit (MLX)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxQwen3_06BFiles, 9, 351383618,
     4096, true},
    {"mlx-maple-preview-2bit", "mlx-maple-preview",
     "DeepGrove Maple Preview 2-bit (MLX)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxMaplePreviewFiles, 13, 5330252282LL, 128000, true},
    {"mlx-llama-3.1-nemotron-nano-8b-v1-4bit", "mlx-nemotron-nano",
     "NVIDIA Llama 3.1 Nemotron Nano 8B 4-bit (MLX)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxNemotronNano8BFiles, 8,
     4534806075LL, 131072, false},
    {"mlx-nemotron-mini-4b-instruct-4bit", "mlx-nemotron-mini",
     "NVIDIA Nemotron Mini 4B Instruct 4-bit (MLX)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxNemotronMini4BFiles, 6,
     2392679103LL, 4096, false},
    // PrismML Bonsai family 1-bit MLX. Needs the narrow Prism kernels carried
    // by the canonical-first RunAnywhere MLX/mlx-swift forks pinned in the
    // Swift manifests and resolved files.
    {"mlx-bonsai-1.7b-1bit", "mlx-bonsai-1.7b", "MLX Bonsai-1.7B 1-bit",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxBonsai1_7B1BitFiles, 8,
     269060904LL, 4096, true},
    {"mlx-bonsai-4b-1bit", "mlx-bonsai-4b", "MLX Bonsai-4B 1-bit",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxBonsai4B1BitFiles, 8,
     628865840LL, 4096, true},
    {"mlx-bonsai-8b-1bit", "mlx-bonsai-8b", "MLX Bonsai-8B 1-bit",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxBonsai8B1BitFiles, 8,
     1280131424LL, 4096, true},
    // PrismML Bonsai-27B 1-bit MLX (~5.1 GB safetensors). Experimental —
    // requires mlx-swift-lm support for qwen3_5 / 1-bit Bonsai.
    {"mlx-bonsai-27b-1bit", "mlx-bonsai", "MLX Bonsai-27B 1-bit",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxBonsai27B1BitFiles, 8,
     5129115752LL, 4096, true},
    // PrismML Ternary-Bonsai family at ternary/2-bit MLX. bits=2 was already
    // supported by upstream MLX 0.31.6 before the Prism 1-bit patch, so this
    // needs no additional fork support beyond what Bonsai (above) needs.
    // Verified this session: loaded + generated correctly via the app's
    // Add-from-URL flow (Ternary-Bonsai-1.7B, 64 tok/s, no crash).
    {"mlx-ternary-bonsai-1.7b-2bit", "mlx-ternary-bonsai-1.7b",
     "MLX Ternary-Bonsai-1.7B 2-bit", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxTernaryBonsai1_7B2BitFiles, 6, 484049216LL, 4096, true},
    {"mlx-ternary-bonsai-4b-2bit", "mlx-ternary-bonsai-4b",
     "MLX Ternary-Bonsai-4B 2-bit", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxTernaryBonsai4B2BitFiles, 6, 1131565944LL, 4096, true},
    {"mlx-ternary-bonsai-8b-2bit", "mlx-ternary-bonsai-8b",
     "MLX Ternary-Bonsai-8B 2-bit", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxTernaryBonsai8B2BitFiles, 6, 2303661704LL, 4096, true},
    {"mlx-ternary-bonsai-27b-2bit", "mlx-ternary-bonsai-27b",
     "MLX Ternary-Bonsai-27B 2-bit", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxTernaryBonsai27B2BitFiles, 8, 8490785104LL, 4096, true},
    {"mlx-llama-3.2-1b-instruct-4bit", "mlx-llama3.2",
     "Llama 3.2 1B Instruct 4-bit (MLX)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxLlama32_1BFiles, 6, 712575975, 0, false},
    {"mlx-qwen2-vl-2b-instruct-4bit", "mlx-qwen2-vl",
     "Qwen2-VL 2B Instruct 4-bit (MLX)", v1::MODEL_CATEGORY_MULTIMODAL,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxQwen2Vl2BFiles, 11, 1261853827, 2048, false},
    {"mlx-fastvlm-0.5b-bf16", "mlx-fastvlm", "FastVLM 0.5B bf16 (MLX)",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxFastVlm05BFiles, 14, 1256926974,
     2048, false},
    {"mlx-lfm2.5-vl-3b-4bit", "mlx-lfm2.5-vl", "LFM2.5-VL 3B 4-bit (MLX)",
     v1::MODEL_CATEGORY_MULTIMODAL, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxLfm2_5Vl3BFiles, 9,
     2388258432LL, 4096, false},
    {"mlx-qwen3-embedding-0.6b-4bit-dwq", "mlx-qwen3-embed",
     "Qwen3 Embedding 0.6B 4-bit DWQ (MLX)", v1::MODEL_CATEGORY_EMBEDDING,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxQwen3Embedding06BFiles, 11, 351230811, 0, false},
    {"mlx-qwen3-asr-0.6b-8bit", "mlx-qwen3-asr", "Qwen3-ASR 0.6B 8-bit (MLX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxQwen3Asr06BFiles, 9, 1010773761,
     0, false},
    {"mlx-glm-asr-nano-2512-4bit", "mlx-glm-asr",
     "GLM-ASR Nano 2512 4-bit (MLX)", v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxGlmAsrNano2512Files, 9, 1288437789, 0, false},
    {"mlx-parakeet-ctc-1.1b", "mlx-parakeet-ctc",
     "NVIDIA Parakeet CTC 1.1B (MLX)", v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxParakeetCtc11BFiles, 2, 4250718357LL, 0, false},
    {"mlx-parakeet-tdt-0.6b-v2", "mlx-parakeet-tdt-v2",
     "NVIDIA Parakeet TDT 0.6B v2 (MLX)", v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxParakeetTdtV2Files, 2, 2471596080LL, 0, false},
    {"mlx-parakeet-tdt-0.6b-v3", "mlx-parakeet-tdt-v3",
     "NVIDIA Parakeet TDT 0.6B v3 (MLX)", v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxParakeetTdtV3Files, 2, 2508532829LL, 0, false},
    {"mlx-parakeet-rnnt-1.1b", "mlx-parakeet-rnnt",
     "NVIDIA Parakeet RNNT 1.1B (MLX)", v1::MODEL_CATEGORY_SPEECH_RECOGNITION,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxParakeetRnnt11BFiles, 2, 4282283914LL, 0, false},
    {"mlx-nemotron-3.5-asr-streaming-0.6b-8bit", "mlx-nemotron-asr",
     "NVIDIA Nemotron 3.5 Streaming ASR 0.6B 8-bit (MLX)",
     v1::MODEL_CATEGORY_SPEECH_RECOGNITION, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxNemotronStreamingAsrFiles, 2,
     755758528LL, 0, false},
    {"mlx-qwen3-tts-12hz-0.6b-base-8bit", "mlx-qwen3-tts",
     "Qwen3-TTS 12Hz 0.6B Base 8-bit (MLX)",
     v1::MODEL_CATEGORY_SPEECH_SYNTHESIS, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxQwen3Tts06BBaseFiles, 12,
     1991299138, 0, false},
    {"mlx-soprano-1.1-80m-5bit", "mlx-soprano", "Soprano 1.1 80M 5-bit (MLX)",
     v1::MODEL_CATEGORY_SPEECH_SYNTHESIS, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxSoprano1180M5BitFiles, 7,
     82220814, 0, false},

    // Google Gemma 4 family (MLX). config.json model_type "gemma4" /
    // "gemma4_unified" (12B), both registered in the pinned mlx-swift-lm
    // 3.31.5 LLMTypeRegistry/VLMTypeRegistry — verified by reading the
    // checked-out package source this session (not assumed). Licensed under
    // Apache 2.0; preserve the upstream license and attribution notices.
    {"mlx-gemma-4-e2b-it-4bit", "mlx-gemma4-e2b", "Gemma 4 E2B IT 4-bit (MLX)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxGemma4E2BFiles, 8, 3550670554LL,
     4096, false},
    {"mlx-gemma-4-e4b-it-qat-4bit", "mlx-gemma4-e4b",
     "Gemma 4 E4B IT QAT 4-bit (MLX)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxGemma4E4BFiles, 9, 6798307742LL, 4096, false},
    {"mlx-gemma-4-12b-it-qat-4bit", "mlx-gemma4-12b",
     "Gemma 4 12B IT QAT 4-bit (MLX)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxGemma4_12BFiles, 10, 10987772430LL, 4096, false},
    {"mlx-gemma-4-26b-a4b-it-4bit", "mlx-gemma4-26b-a4b",
     "Gemma 4 26B-A4B IT 4-bit (MLX, MoE)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxGemma4_26BA4BFiles, 10, 15341205776LL, 4096, false},
    // The plain 4bit variant, NOT "-qat-4bit" — that name does not resolve to
    // a clean repo (verified this session); this is the largest dense Gemma 4.
    {"mlx-gemma-4-31b-it-4bit", "mlx-gemma4-31b", "Gemma 4 31B IT 4-bit (MLX)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxGemma4_31BFiles, 11,
     18412016676LL, 4096, false},

    // Qwen3.6-35B-A3B (MoE) — config.json model_type "qwen3_5_moe",
    // registered in mlx-swift-lm 3.31.5's LLMTypeRegistry.
    {"mlx-qwen3.6-35b-a3b-4bit", "mlx-qwen3.6-35b",
     "Qwen3.6 35B-A3B 4-bit (MLX, MoE)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxQwen3_6_35BA3BFiles, 15, 20402204271LL, 4096, true},
    // Qwen3.8-27B (dense) — config.json model_type "qwen3_5", registered.
    {"mlx-qwen3.8-27b-4bit", "mlx-qwen3.8-27b", "Qwen3.8 27B 4-bit (MLX)",
     v1::MODEL_CATEGORY_LANGUAGE, v1::INFERENCE_FRAMEWORK_MLX,
     v1::MODEL_FORMAT_SAFETENSORS, nullptr, kMlxQwen3_8_27BFiles, 13,
     16054541349LL, 4096, true},

    // IBM Granite 4.1 family (MLX). config.json model_type "granite",
    // registered in mlx-swift-lm 3.31.5's LLMTypeRegistry.
    {"mlx-granite-4.1-3b-4bit", "mlx-granite4.1-3b",
     "IBM Granite 4.1 3B 4-bit (MLX)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxGranite4_1_3BFiles, 7, 2127162429LL, 4096, false},
    // A real, official mlx-community 8B 4-bit quant does exist (Apache-2.0,
    // model_type "granite") — verified via HF API this session, despite the
    // original assumption that none did; added for parity with 3B/30B.
    {"mlx-granite-4.1-8b-4bit", "mlx-granite4.1-8b",
     "IBM Granite 4.1 8B 4-bit (MLX)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxGranite4_1_8BFiles, 7, 5238406779LL, 4096, false},
    {"mlx-granite-4.1-30b-4bit", "mlx-granite4.1-30b",
     "IBM Granite 4.1 30B 4-bit (MLX)", v1::MODEL_CATEGORY_LANGUAGE,
     v1::INFERENCE_FRAMEWORK_MLX, v1::MODEL_FORMAT_SAFETENSORS, nullptr,
     kMlxGranite4_1_30BFiles, 10, 18041976573LL, 4096, false},

    // Muse Glimmer 30B (MLX) and Nemotron-3-Nano-Omni-30B-A3B-Reasoning (MLX)
    // are deliberately NOT registered here. Their config.json model_types
    // ("muse_glimmer" and "NemotronH_Nano_Omni_Reasoning_V3" respectively) are
    // NOT present in the pinned mlx-swift-lm 3.31.5 LLMTypeRegistry /
    // VLMTypeRegistry (checked the checked-out package source directly:
    // .build/checkouts/mlx-swift-lm/Libraries/{MLXLLM,MLXVLM}/*Factory.swift —
    // only "nemotron_h" exists, a different string). Loading either would fail
    // with ModelFactoryError.unsupportedModelType. The GGUF+mmproj rows above
    // (llama.cpp) remain the way to run these two on rcli.
};

constexpr size_t kCatalogCount = sizeof(kCatalog) / sizeof(kCatalog[0]);

rac_result_t register_entry(const CatalogEntry &entry) {
  // CoreML bundles (a directory of compiled .mlmodelc sub-models) don't fit the
  // URL / multi-file download-factory grammar, which rejects a bare repo ref.
  // Register the ModelInfo directly so the id resolves in the general registry
  // (and `rcli list` shows it); the bundle itself is fetched by the diffusion
  // pipeline or supplied to `rcli image --model <local path>`.
  if (entry.framework == v1::INFERENCE_FRAMEWORK_COREML) {
    v1::ModelInfo model;
    model.set_id(entry.id);
    model.set_name(entry.name);
    model.set_category(entry.category);
    model.set_framework(entry.framework);
    model.set_format(entry.format);
    if (entry.url != nullptr) {
      model.set_download_url(entry.url);
    }
    model.set_download_size_bytes(entry.download_size_bytes);
    model.set_source(v1::MODEL_SOURCE_REMOTE);
    const std::string bytes = proto::serialize(model);
    return rac_model_registry_register_proto(
        rac_get_model_registry(),
        reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size());
  }

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
    if (entry.memory_required_bytes > 0) {
      request.set_memory_required_bytes(entry.memory_required_bytes);
    }
    if (entry.context_length > 0) {
      request.set_context_length(entry.context_length);
    }
    if (entry.supports_thinking) {
      request.set_supports_thinking(true);
    }
    if (entry.cua_profile != nullptr && entry.cua_profile[0] != '\0') {
      request.set_cua_profile(entry.cua_profile);
    }
    for (size_t i = 0; i < entry.file_count; ++i) {
      runanywhere::v1::ModelFileDescriptor *file = request.add_files();
      file->set_url(entry.files[i].url);
      file->set_filename(entry.files[i].filename);
      file->set_is_optional(!entry.files[i].required);
      if (entry.files[i].size_bytes > 0) {
        file->set_size_bytes(entry.files[i].size_bytes);
      }
      if (entry.files[i].checksum_sha256 != nullptr) {
        file->set_checksum_sha256(entry.files[i].checksum_sha256);
      }
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

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

constexpr int64_t MB = 1024LL * 1024LL;

// ids/URLs verbatim from: examples/ios ModelCatalogBootstrap.swift, Android
// ModelCatalog.kt, web model-catalog.ts and
// tests/scripts/download-test-models.sh (qwen3-0.6b Q8_0 matches the Linux test
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
    // PrismML Bonsai family Q1_0 — needs PrismML llama.cpp fork
    // (LLAMACPP_VERSION=prism-b9591-62061f9). Exact artifact byte sizes.
    // NOTE: Ternary-Bonsai GGUF (Q2_0/PQ2_0) is intentionally NOT registered —
    // verified via `rcli run hf.co/prism-ml/Ternary-Bonsai-1.7B-gguf:Q2_0`:
    // the pinned fork rejects it with "invalid ggml type 142" (it only added
    // Q1_0/plain-Bonsai support, not Ternary-Bonsai's tensor encoding).
    // Ternary-Bonsai MLX (below) works fine.
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
    {"all-minilm-l6-v2", "minilm", "All-MiniLM-L6-v2 (Embeddings)",
     v1::MODEL_CATEGORY_EMBEDDING, v1::INFERENCE_FRAMEWORK_ONNX,
     v1::MODEL_FORMAT_ONNX, nullptr, kMiniLmFiles, 2, 90 * MB, 0, false},

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
    // PrismML Bonsai family 1-bit MLX. Needs the PrismML mlx-swift fork
    // (bits=1 quantization support) pinned in Package.swift/Package.resolved.
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

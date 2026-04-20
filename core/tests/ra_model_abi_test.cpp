// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include <gtest/gtest.h>

#include "../abi/ra_model.h"
#include "../abi/ra_primitives.h"

TEST(RaModelAbi, FrameworkSupportMatrix) {
    EXPECT_EQ(ra_framework_supports("llamacpp", "llm"),       1);
    EXPECT_EQ(ra_framework_supports("llamacpp", "stt"),       0);
    EXPECT_EQ(ra_framework_supports("onnx", "stt"),           1);
    EXPECT_EQ(ra_framework_supports("onnx", "vad"),           1);
    EXPECT_EQ(ra_framework_supports("onnx", "embedding"),     1);
    EXPECT_EQ(ra_framework_supports("whisperkit", "stt"),     1);
    EXPECT_EQ(ra_framework_supports("whisperkit", "llm"),     0);
    EXPECT_EQ(ra_framework_supports("metalrt", "llm"),        1);
    EXPECT_EQ(ra_framework_supports("metalrt", "vlm"),        1);
    EXPECT_EQ(ra_framework_supports("genie", "llm"),          1);
    EXPECT_EQ(ra_framework_supports("foundation_models", "llm"), 1);
    EXPECT_EQ(ra_framework_supports("sherpa", "tts"),         1);
    EXPECT_EQ(ra_framework_supports("unknown", "llm"),        0);
}

TEST(RaModelAbi, DetectFormat) {
    EXPECT_EQ(ra_model_detect_format("https://x/foo.gguf"), RA_FORMAT_GGUF);
    EXPECT_EQ(ra_model_detect_format("/a/b/model.onnx"),    RA_FORMAT_ONNX);
    EXPECT_EQ(ra_model_detect_format("model.mlmodelc"),     RA_FORMAT_COREML);
    EXPECT_EQ(ra_model_detect_format("model.mlpackage"),    RA_FORMAT_COREML);
    EXPECT_EQ(ra_model_detect_format("weights.safetensors"), RA_FORMAT_SAFETENSORS);
    EXPECT_EQ(ra_model_detect_format("model.tflite"),       RA_FORMAT_TFLITE);
    EXPECT_EQ(ra_model_detect_format("model.pte"),          RA_FORMAT_EXECUTORCH_PTE);
    EXPECT_EQ(ra_model_detect_format("model.pt"),           RA_FORMAT_PYTORCH);
    EXPECT_EQ(ra_model_detect_format("model.bin"),          RA_FORMAT_BIN);
    EXPECT_EQ(ra_model_detect_format("unknown.xyz"),        RA_FORMAT_UNKNOWN);
    EXPECT_EQ(ra_model_detect_format(nullptr),              RA_FORMAT_UNKNOWN);
}

TEST(RaModelAbi, DetectArchiveFormat) {
    EXPECT_EQ(ra_model_detect_archive_format("pack.zip"),       1);
    EXPECT_EQ(ra_model_detect_archive_format("pack.tar.gz"),    2);
    EXPECT_EQ(ra_model_detect_archive_format("pack.tgz"),       2);
    EXPECT_EQ(ra_model_detect_archive_format("pack.tar.bz2"),   3);
    EXPECT_EQ(ra_model_detect_archive_format("pack.tar.xz"),    4);
    EXPECT_EQ(ra_model_detect_archive_format("pack.tar"),       5);
    EXPECT_EQ(ra_model_detect_archive_format("pack.gguf"),      0);
}

TEST(RaModelAbi, InferCategory) {
    EXPECT_EQ(ra_model_infer_category("whisper-base"),           RA_MODEL_CATEGORY_STT);
    EXPECT_EQ(ra_model_infer_category("silero-vad-v5"),          RA_MODEL_CATEGORY_VAD);
    EXPECT_EQ(ra_model_infer_category("stable-diffusion-v1-5"),  RA_MODEL_CATEGORY_DIFFUSION);
    EXPECT_EQ(ra_model_infer_category("bge-rerank-base"),        RA_MODEL_CATEGORY_RERANK);
    EXPECT_EQ(ra_model_infer_category("bge-small-en"),           RA_MODEL_CATEGORY_EMBEDDING);
    EXPECT_EQ(ra_model_infer_category("hey-jarvis"),             RA_MODEL_CATEGORY_WAKEWORD);
    EXPECT_EQ(ra_model_infer_category("kokoro-tts-v1"),          RA_MODEL_CATEGORY_TTS);
    EXPECT_EQ(ra_model_infer_category("llava-1.5"),              RA_MODEL_CATEGORY_VLM);
    EXPECT_EQ(ra_model_infer_category("qwen-2.5-7b"),            RA_MODEL_CATEGORY_LLM);
}

TEST(RaModelAbi, ArtifactPredicates) {
    EXPECT_EQ(ra_artifact_is_archive("file.zip"),      1);
    EXPECT_EQ(ra_artifact_is_archive("file.gguf"),     0);
    EXPECT_EQ(ra_artifact_is_directory("x.mlmodelc"),  1);
    EXPECT_EQ(ra_artifact_is_directory("x.mlpackage"), 1);
    EXPECT_EQ(ra_artifact_is_directory("x.gguf"),      0);
}

TEST(RaModelAbi, SupportMatrixJsonNonEmpty) {
    char* json = nullptr;
    ASSERT_EQ(ra_framework_support_matrix_json(&json), RA_OK);
    ASSERT_TRUE(json);
    EXPECT_GT(std::string(json).size(), 10u);
    ra_model_string_free(json);
}

/**
 * HybridRunAnywhereCore+AudioMath.cpp
 *
 * Sync thunks to commons audio / embeddings pure math:
 *   - rac_audio_float32_to_wav / rac_audio_pcm16_to_float32 / rac_audio_int16_to_wav
 *   - rac_embeddings_norm / rac_embeddings_similarity
 *
 * Keeps JS/TS from reimplementing PCM quantization or vector math.
 */
#include "HybridRunAnywhereCore+Common.hpp"

#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_types.h"

#include <cstdint>
#include <stdexcept>
#include <vector>

namespace margelo::nitro::runanywhere {
namespace {

const uint8_t *bufferData(const std::shared_ptr<ArrayBuffer> &buffer) {
  return buffer ? buffer->data() : nullptr;
}

size_t bufferSize(const std::shared_ptr<ArrayBuffer> &buffer) {
  return buffer ? buffer->size() : 0;
}

std::shared_ptr<ArrayBuffer> copyOwnedBytes(void *data, size_t size) {
  if (!data || size == 0) {
    if (data) {
      rac_free(data);
    }
    return ArrayBuffer::allocate(0);
  }
  auto out = ArrayBuffer::copy(static_cast<uint8_t *>(data), size);
  rac_free(data);
  return out;
}

} // namespace

std::shared_ptr<ArrayBuffer> HybridRunAnywhereCore::audioFloat32ToWav(
    const std::shared_ptr<ArrayBuffer> &pcmBytes, double sampleRate) {
  const size_t size = bufferSize(pcmBytes);
  if (size == 0) {
    return ArrayBuffer::allocate(0);
  }
  void *wavData = nullptr;
  size_t wavSize = 0;
  const rac_result_t rc = rac_audio_float32_to_wav(
      bufferData(pcmBytes), size, static_cast<int32_t>(sampleRate), &wavData,
      &wavSize);
  if (rc != RAC_SUCCESS) {
    rac_free(wavData);
    throw std::runtime_error(std::string("rac_audio_float32_to_wav failed: ") +
                             rac_error_message(rc));
  }
  return copyOwnedBytes(wavData, wavSize);
}

std::shared_ptr<ArrayBuffer> HybridRunAnywhereCore::audioPcm16ToFloat32(
    const std::shared_ptr<ArrayBuffer> &pcm16Bytes) {
  const size_t size = bufferSize(pcm16Bytes);
  if (size == 0) {
    return ArrayBuffer::allocate(0);
  }
  if (size % sizeof(int16_t) != 0) {
    throw std::runtime_error(
        "rac_audio_pcm16_to_float32: pcm16 byte length must be even");
  }
  const size_t nSamples = size / sizeof(int16_t);
  std::vector<float> out(nSamples);
  const rac_result_t rc = rac_audio_pcm16_to_float32(
      reinterpret_cast<const int16_t *>(bufferData(pcm16Bytes)), nSamples,
      out.data());
  if (rc != RAC_SUCCESS) {
    throw std::runtime_error(std::string("rac_audio_pcm16_to_float32 failed: ") +
                             rac_error_message(rc));
  }
  return ArrayBuffer::copy(reinterpret_cast<uint8_t *>(out.data()),
                           out.size() * sizeof(float));
}

std::shared_ptr<ArrayBuffer> HybridRunAnywhereCore::audioInt16ToWav(
    const std::shared_ptr<ArrayBuffer> &pcm16Bytes, double sampleRate) {
  const size_t size = bufferSize(pcm16Bytes);
  if (size == 0) {
    return ArrayBuffer::allocate(0);
  }
  void *wavData = nullptr;
  size_t wavSize = 0;
  const rac_result_t rc = rac_audio_int16_to_wav(
      bufferData(pcm16Bytes), size, static_cast<int32_t>(sampleRate), &wavData,
      &wavSize);
  if (rc != RAC_SUCCESS) {
    rac_free(wavData);
    throw std::runtime_error(std::string("rac_audio_int16_to_wav failed: ") +
                             rac_error_message(rc));
  }
  return copyOwnedBytes(wavData, wavSize);
}

double HybridRunAnywhereCore::embeddingsNorm(
    const std::shared_ptr<ArrayBuffer> &vectorBytes) {
  const size_t size = bufferSize(vectorBytes);
  if (size == 0) {
    return 0.0;
  }
  if (size % sizeof(float) != 0) {
    throw std::runtime_error(
        "rac_embeddings_norm: vector byte length must be a multiple of 4");
  }
  float norm = 0.0f;
  const rac_result_t rc = rac_embeddings_norm(
      reinterpret_cast<const float *>(bufferData(vectorBytes)),
      size / sizeof(float), &norm);
  if (rc != RAC_SUCCESS) {
    throw std::runtime_error(std::string("rac_embeddings_norm failed: ") +
                             rac_error_message(rc));
  }
  return static_cast<double>(norm);
}

double HybridRunAnywhereCore::embeddingsSimilarity(
    const std::shared_ptr<ArrayBuffer> &lhsBytes,
    const std::shared_ptr<ArrayBuffer> &rhsBytes) {
  const size_t lhsSize = bufferSize(lhsBytes);
  const size_t rhsSize = bufferSize(rhsBytes);
  if (lhsSize % sizeof(float) != 0 || rhsSize % sizeof(float) != 0) {
    throw std::runtime_error(
        "rac_embeddings_similarity: vector byte length must be a multiple of 4");
  }
  float similarity = 0.0f;
  const rac_result_t rc = rac_embeddings_similarity(
      reinterpret_cast<const float *>(bufferData(lhsBytes)),
      lhsSize / sizeof(float),
      reinterpret_cast<const float *>(bufferData(rhsBytes)),
      rhsSize / sizeof(float), &similarity);
  if (rc != RAC_SUCCESS) {
    throw std::runtime_error(std::string("rac_embeddings_similarity failed: ") +
                             rac_error_message(rc));
  }
  return static_cast<double>(similarity);
}

} // namespace margelo::nitro::runanywhere

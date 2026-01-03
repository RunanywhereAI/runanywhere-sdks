/**
 * @file rac_audio_utils.h
 * @brief RunAnywhere Commons - Audio Utility Functions
 *
 * Provides audio format conversion utilities used across the SDK.
 * This centralizes audio processing logic that was previously duplicated
 * in Swift/Kotlin SDKs.
 */

#ifndef RAC_AUDIO_UTILS_H
#define RAC_AUDIO_UTILS_H

#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// AUDIO CONVERSION API
// =============================================================================

/**
 * @brief Convert Float32 PCM samples to WAV format (Int16 PCM with header)
 *
 * TTS backends typically output raw Float32 PCM samples in range [-1.0, 1.0].
 * This function converts them to a complete WAV file that can be played by
 * standard audio players (AVAudioPlayer on iOS, MediaPlayer on Android, etc.).
 *
 * WAV format details:
 * - RIFF header with WAVE format
 * - fmt chunk: PCM format (1), mono (1 channel), Int16 samples
 * - data chunk: Int16 samples (scaled from Float32)
 *
 * @param pcm_data Input Float32 PCM samples
 * @param pcm_size Size of pcm_data in bytes (must be multiple of 4)
 * @param sample_rate Sample rate in Hz (e.g., 22050 for Piper TTS)
 * @param out_wav_data Output: WAV file data (owned, must be freed with rac_free)
 * @param out_wav_size Output: Size of WAV data in bytes
 * @return RAC_SUCCESS or error code
 *
 * @note The caller owns the returned wav_data and must free it with rac_free()
 *
 * Example usage:
 * @code
 * void* wav_data = NULL;
 * size_t wav_size = 0;
 * rac_result_t result = rac_audio_float32_to_wav(
 *     pcm_samples, pcm_size, RAC_TTS_DEFAULT_SAMPLE_RATE, &wav_data, &wav_size);
 * if (result == RAC_SUCCESS) {
 *     // Use wav_data...
 *     rac_free(wav_data);
 * }
 * @endcode
 */
RAC_API rac_result_t rac_audio_float32_to_wav(const void* pcm_data, size_t pcm_size,
                                              int32_t sample_rate, void** out_wav_data,
                                              size_t* out_wav_size);

/**
 * @brief Convert Int16 PCM samples to WAV format
 *
 * Similar to rac_audio_float32_to_wav but for Int16 input samples.
 *
 * @param pcm_data Input Int16 PCM samples
 * @param pcm_size Size of pcm_data in bytes (must be multiple of 2)
 * @param sample_rate Sample rate in Hz
 * @param out_wav_data Output: WAV file data (owned, must be freed with rac_free)
 * @param out_wav_size Output: Size of WAV data in bytes
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_audio_int16_to_wav(const void* pcm_data, size_t pcm_size,
                                            int32_t sample_rate, void** out_wav_data,
                                            size_t* out_wav_size);

/**
 * @brief Get WAV header size in bytes
 *
 * @return WAV header size (always 44 bytes for standard PCM WAV)
 */
RAC_API size_t rac_audio_wav_header_size(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_AUDIO_UTILS_H */

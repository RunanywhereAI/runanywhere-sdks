/**
 * @file rac_audio_utils.h
 * @brief RunAnywhere Commons - Audio Utility Functions
 *
 * Provides audio format conversion and level-meter utilities used across the
 * SDK. This centralizes audio processing logic that was previously duplicated
 * in Swift/Kotlin/Web SDKs.
 *
 * PCM16 scaling convention (canonical, Kotlin-aligned):
 *   - Decode: float = int16 / 32768.0f
 *       INT16_MIN (-32768) → -1.0f
 *       INT16_MAX ( 32767) → 32767/32768 ≈ 0.999969482f (not +1.0f)
 *   - Encode: clamp finite samples to [-1, 1], multiply by 32768.0f, round to
 *       nearest integer, saturate to [-32768, 32767]. Non-finite samples → 0.
 *
 * Historical Web encode paths that used /32767 or *0x7fff (symmetric max) lose
 * the coin-flip; see thoughts/.../reports/W1-C_audio.json for the numeric delta.
 *
 * Swift CRACommons mirror of core/include/rac/core/rac_audio_utils.h
 */

#ifndef RAC_AUDIO_UTILS_H
#define RAC_AUDIO_UTILS_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Default dBFS floor for rac_audio_compute_level_normalized (−60 dB → 0.0). */
#define RAC_AUDIO_LEVEL_FLOOR_DB (-60.0f)

/** Full-scale divisor / multiplier for the canonical PCM16 ↔ float32 mapping. */
#define RAC_AUDIO_PCM16_SCALE (32768.0f)

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
 * - data chunk: Int16 samples (scaled from Float32 via rac_audio_float32_to_pcm16)
 *
 * @param pcm_data Input Float32 PCM samples
 * @param pcm_size Size of pcm_data in bytes (must be multiple of 4)
 * @param sample_rate Sample rate in Hz (e.g., 22050 for Piper TTS)
 * @param out_wav_data Output: WAV file data (owned, must be freed with rac_free)
 * @param out_wav_size Output: Size of WAV data in bytes
 * @return RAC_SUCCESS or error code
 *
 * @note The caller owns the returned wav_data and must free it with rac_free()
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

/**
 * @brief Convert Int16 PCM samples to Float32 in approximately [-1.0, 1.0].
 *
 * Divides each sample by RAC_AUDIO_PCM16_SCALE (32768.0f). Caller owns both
 * buffers; @p out MUST hold at least @p n_samples floats.
 *
 * @return RAC_SUCCESS, or RAC_ERROR_NULL_POINTER when @p n_samples > 0 and
 *         @p in or @p out is NULL. A zero sample count is a no-op success.
 */
RAC_API rac_result_t rac_audio_pcm16_to_float32(const int16_t* in, size_t n_samples, float* out);

/**
 * @brief Quantize Float32 samples in [-1.0, 1.0] to Int16 PCM.
 *
 * Finite samples are clamped to [-1, 1], multiplied by 32768.0f, rounded to the
 * nearest integer, and saturated to [-32768, 32767]. Non-finite values (NaN,
 * ±Inf) become 0. Caller owns both buffers; @p out MUST hold at least
 * @p n_samples int16 values.
 *
 * @return RAC_SUCCESS, or RAC_ERROR_NULL_POINTER when @p n_samples > 0 and
 *         @p in or @p out is NULL. A zero sample count is a no-op success.
 */
RAC_API rac_result_t rac_audio_float32_to_pcm16(const float* in, size_t n_samples, int16_t* out);

/**
 * @brief Compute linear RMS of Float32 PCM samples in [-1.0, 1.0].
 *
 * Accumulates in double precision. A zero sample count writes 0.0 and succeeds
 * when @p out_rms is non-NULL (platforms use that as the empty-frame energy).
 *
 * @param samples Pointer to float32 PCM samples (may be NULL when count == 0).
 * @param count   Number of samples.
 * @param out_rms Output linear RMS (always >= 0).
 * @return RAC_SUCCESS, or RAC_ERROR_NULL_POINTER when @p out_rms is NULL or
 *         when @p count > 0 and @p samples is NULL.
 */
RAC_API rac_result_t rac_audio_compute_rms(const float* samples, size_t count, float* out_rms);

/**
 * @brief Compute audio RMS level in dBFS.
 *
 * Runs rac_audio_compute_rms and converts to decibels. Centralises the
 * level-meter DSP that used to be hand-rolled in each platform SDK (Swift
 * AudioCaptureManager, etc.).
 *
 * @param samples Pointer to float32 PCM samples in [-1.0, 1.0].
 * @param count   Number of samples.
 * @param out_db  Output decibel level (always negative or zero; -inf clamped
 *                to -100.0 dB if the signal is silent / below threshold).
 * @return RAC_SUCCESS on success, RAC_ERROR_NULL_POINTER on NULL inputs or
 *         zero count.
 */
RAC_API rac_result_t rac_audio_compute_level_db(const float* samples, size_t count, float* out_db);

/**
 * @brief Compute a normalized audio level in [0.0, 1.0] from Float32 PCM.
 *
 * Runs the same RMS→dBFS path as rac_audio_compute_level_db, then maps
 * [floor_db, 0] → [0, 1] and clamps. Pass RAC_AUDIO_LEVEL_FLOOR_DB (−60) for
 * the historical platform-SDK meter window.
 *
 * @param samples  Float32 PCM in [-1.0, 1.0].
 * @param count    Number of samples (must be > 0).
 * @param floor_db Negative dBFS floor that maps to 0.0 (e.g. −60). Must be < 0.
 * @param out_0_1  Output level in [0.0, 1.0].
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER, or RAC_ERROR_INVALID_ARGUMENT
 *         when floor_db >= 0.
 */
RAC_API rac_result_t rac_audio_compute_level_normalized(const float* samples, size_t count,
                                                       float floor_db, float* out_0_1);

/**
 * @brief Resample mono Float32 PCM with linear interpolation.
 *
 * Allocates the output buffer with rac_alloc; caller must rac_free(*out).
 * When @p in_rate == @p out_rate the samples are copied. Both rates must be > 0.
 *
 * @param in         Input mono frames.
 * @param in_frames  Number of input frames.
 * @param in_rate    Source sample rate in Hz.
 * @param out_rate   Destination sample rate in Hz.
 * @param out        Output: allocated float buffer (may be NULL when out_frames==0).
 * @param out_frames Output: number of frames written.
 * @return RAC_SUCCESS or an error code.
 */
RAC_API rac_result_t rac_audio_resample_f32(const float* in, size_t in_frames, int32_t in_rate,
                                           int32_t out_rate, float** out, size_t* out_frames);

/**
 * @brief Convert a raw interleaved PCM byte count to integer milliseconds.
 *
 * Uses @p format→sample_rate, channels, and bits_per_sample (16 or 32) to
 * derive bytes-per-frame. Truncates toward zero (same policy as the historical
 * STT duration estimate).
 *
 * @param byte_count Size of the PCM payload in bytes.
 * @param format     Sample rate / channel / bit-depth description.
 * @param out_ms     Output duration in milliseconds.
 * @return RAC_SUCCESS or RAC_ERROR_INVALID_ARGUMENT / RAC_ERROR_NULL_POINTER.
 */
RAC_API rac_result_t rac_audio_pcm_bytes_to_ms(size_t byte_count, const rac_audio_format_t* format,
                                              int64_t* out_ms);

/**
 * @brief Decode a 16-bit PCM WAV (RIFF) buffer to mono Float32 samples.
 *
 * Scans RIFF sub-chunks for `fmt ` and `data`. Stereo is down-mixed to mono.
 * Only uncompressed PCM (format tag 1) at 16 bits per sample is supported.
 * Allocates @p out_samples with rac_alloc; caller must rac_free(*out_samples).
 *
 * @param wav_data        Input WAV bytes.
 * @param wav_size        Size of @p wav_data in bytes.
 * @param out_samples     Output: allocated float buffer (may be NULL when
 *                        out_n_samples == 0).
 * @param out_n_samples   Output: number of mono frames written.
 * @param out_sample_rate Output: sample rate from the fmt chunk.
 * @return RAC_SUCCESS, RAC_ERROR_NULL_POINTER, RAC_ERROR_INVALID_ARGUMENT, or
 *         RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED.
 */
RAC_API rac_result_t rac_audio_wav_to_float32(const void* wav_data, size_t wav_size,
                                             float** out_samples, size_t* out_n_samples,
                                             int32_t* out_sample_rate);

#ifdef __cplusplus
}
#endif

#endif /* RAC_AUDIO_UTILS_H */

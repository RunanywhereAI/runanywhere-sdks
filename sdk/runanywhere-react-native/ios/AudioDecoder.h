/**
 * AudioDecoder.h
 * 
 * iOS audio file decoder using built-in AudioToolbox.
 * Converts any audio format (M4A, CAF, WAV, etc.) to PCM float32 samples.
 */

#ifndef AudioDecoder_h
#define AudioDecoder_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Decode an audio file to PCM float32 samples at 16kHz mono
 * Works with any iOS-supported audio format (M4A, CAF, WAV, MP3, etc.)
 * 
 * @param filePath Path to the audio file (null-terminated C string)
 * @param samples Output: pointer to float array (caller must free with ra_free_audio_samples)
 * @param numSamples Output: number of samples
 * @param sampleRate Output: sample rate (will be 16000 Hz)
 * @return 1 on success, 0 on failure
 */
int ra_decode_audio_file(const char* filePath, float** samples, size_t* numSamples, int* sampleRate);

/**
 * Free samples allocated by ra_decode_audio_file
 */
void ra_free_audio_samples(float* samples);

#ifdef __cplusplus
}
#endif

#endif /* AudioDecoder_h */



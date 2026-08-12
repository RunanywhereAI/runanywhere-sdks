/**
 * AudioCaptureLevel.mm
 *
 * ObjC++ bridge to cpp/AudioCaptureLevel.cpp (commons rac_audio_*).
 */
#import "AudioCaptureLevel.h"

#include "AudioCaptureLevel.hpp"

@implementation AudioCaptureLevel

+ (double)normalizedFromFloat32Samples:(const float *)samples
                                 count:(NSInteger)count {
  if (samples == NULL || count <= 0) {
    return 0.0;
  }
  return ra_audio_capture_level_normalized_f32(samples, (size_t)count);
}

+ (double)normalizedFromPcm16Le:(NSData *)pcm16le {
  if (pcm16le == nil || pcm16le.length < 2) {
    return 0.0;
  }
  const NSUInteger even = pcm16le.length - (pcm16le.length % 2);
  if (even < 2) {
    return 0.0;
  }
  const int16_t *pcm = (const int16_t *)pcm16le.bytes;
  return ra_audio_capture_level_normalized_pcm16(pcm, even / sizeof(int16_t));
}

@end

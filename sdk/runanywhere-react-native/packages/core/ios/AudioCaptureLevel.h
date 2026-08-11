/**
 * AudioCaptureLevel.h
 *
 * ObjC surface for commons mic-meter math used by HybridAudioCapture.swift.
 */
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioCaptureLevel : NSObject

/** Normalized [0,1] meter from float32 PCM via commons. Empty → 0. */
+ (double)normalizedFromFloat32Samples:(const float *)samples
                                 count:(NSInteger)count;

/** Normalized [0,1] meter from PCM16LE bytes via commons. Empty → 0. */
+ (double)normalizedFromPcm16Le:(NSData *)pcm16le;

@end

NS_ASSUME_NONNULL_END

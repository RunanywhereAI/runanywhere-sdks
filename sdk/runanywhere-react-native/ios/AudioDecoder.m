/**
 * AudioDecoder.m
 * 
 * iOS audio file decoder using built-in AudioToolbox.
 * Converts any audio format (M4A, CAF, WAV, etc.) to PCM float32 samples.
 */

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioDecoder.h"

int ra_decode_audio_file(const char* filePath, float** samples, size_t* numSamples, int* sampleRate) {
    if (!filePath || !samples || !numSamples || !sampleRate) {
        NSLog(@"[AudioDecoder] Invalid parameters");
        return 0;
    }
    
    NSString *path = [NSString stringWithUTF8String:filePath];
    
    // Create URL from file path
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"[AudioDecoder] File not found: %@", path);
        return 0;
    }
    
    NSLog(@"[AudioDecoder] Decoding file: %@", path);
    
    // Open the audio file
    ExtAudioFileRef audioFile = NULL;
    OSStatus status = ExtAudioFileOpenURL((__bridge CFURLRef)fileURL, &audioFile);
    if (status != noErr || !audioFile) {
        NSLog(@"[AudioDecoder] Failed to open audio file: %d", (int)status);
        return 0;
    }
    
    // Get the source format
    AudioStreamBasicDescription srcFormat;
    UInt32 propSize = sizeof(srcFormat);
    status = ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &propSize, &srcFormat);
    if (status != noErr) {
        NSLog(@"[AudioDecoder] Failed to get source format: %d", (int)status);
        ExtAudioFileDispose(audioFile);
        return 0;
    }
    
    NSLog(@"[AudioDecoder] Source format: %.0f Hz, %d channels, %d bits",
          srcFormat.mSampleRate, srcFormat.mChannelsPerFrame, srcFormat.mBitsPerChannel);
    
    // Set the output format to 16kHz mono float32 (optimal for Whisper)
    AudioStreamBasicDescription dstFormat;
    memset(&dstFormat, 0, sizeof(dstFormat));
    dstFormat.mSampleRate = 16000.0;  // 16kHz for Whisper
    dstFormat.mFormatID = kAudioFormatLinearPCM;
    dstFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    dstFormat.mBitsPerChannel = 32;
    dstFormat.mChannelsPerFrame = 1;  // Mono
    dstFormat.mFramesPerPacket = 1;
    dstFormat.mBytesPerFrame = sizeof(float);
    dstFormat.mBytesPerPacket = sizeof(float);
    
    status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(dstFormat), &dstFormat);
    if (status != noErr) {
        NSLog(@"[AudioDecoder] Failed to set output format: %d", (int)status);
        ExtAudioFileDispose(audioFile);
        return 0;
    }
    
    // Get the total number of frames
    SInt64 totalFrames = 0;
    propSize = sizeof(totalFrames);
    status = ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &totalFrames);
    if (status != noErr) {
        NSLog(@"[AudioDecoder] Failed to get frame count: %d", (int)status);
        ExtAudioFileDispose(audioFile);
        return 0;
    }
    
    // Calculate output frames after sample rate conversion
    double ratio = 16000.0 / srcFormat.mSampleRate;
    SInt64 outputFrames = (SInt64)(totalFrames * ratio) + 4096;  // Add buffer
    
    NSLog(@"[AudioDecoder] Total frames: %lld, estimated output: %lld", totalFrames, outputFrames);
    
    // Allocate buffer for all samples
    float *buffer = (float *)malloc(outputFrames * sizeof(float));
    if (!buffer) {
        NSLog(@"[AudioDecoder] Failed to allocate buffer");
        ExtAudioFileDispose(audioFile);
        return 0;
    }
    
    // Read audio data in chunks
    const UInt32 chunkSize = 8192;
    float *tempBuffer = (float *)malloc(chunkSize * sizeof(float));
    size_t totalSamples = 0;
    
    while (1) {
        AudioBufferList bufferList;
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0].mNumberChannels = 1;
        bufferList.mBuffers[0].mDataByteSize = chunkSize * sizeof(float);
        bufferList.mBuffers[0].mData = tempBuffer;
        
        UInt32 framesToRead = chunkSize;
        status = ExtAudioFileRead(audioFile, &framesToRead, &bufferList);
        
        if (status != noErr) {
            NSLog(@"[AudioDecoder] Error reading audio: %d", (int)status);
            break;
        }
        
        if (framesToRead == 0) {
            // End of file
            break;
        }
        
        // Check if we need to grow the buffer
        if (totalSamples + framesToRead > (size_t)outputFrames) {
            outputFrames *= 2;
            float *newBuffer = (float *)realloc(buffer, outputFrames * sizeof(float));
            if (!newBuffer) {
                NSLog(@"[AudioDecoder] Failed to reallocate buffer");
                free(buffer);
                free(tempBuffer);
                ExtAudioFileDispose(audioFile);
                return 0;
            }
            buffer = newBuffer;
        }
        
        // Copy samples
        memcpy(buffer + totalSamples, tempBuffer, framesToRead * sizeof(float));
        totalSamples += framesToRead;
    }
    
    free(tempBuffer);
    ExtAudioFileDispose(audioFile);
    
    if (totalSamples == 0) {
        NSLog(@"[AudioDecoder] No samples decoded");
        free(buffer);
        return 0;
    }
    
    NSLog(@"[AudioDecoder] Decoded %zu samples at 16000 Hz", totalSamples);
    
    *samples = buffer;
    *numSamples = totalSamples;
    *sampleRate = 16000;
    
    return 1;
}

void ra_free_audio_samples(float* samples) {
    if (samples) {
        free(samples);
    }
}


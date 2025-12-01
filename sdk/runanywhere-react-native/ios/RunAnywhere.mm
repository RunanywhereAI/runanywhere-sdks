#import "RunAnywhere.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>  // For audio file reading and conversion
#import <bzlib.h>  // For bz2 decompression

#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTBridge+Private.h>
#import <jsi/jsi.h>
#import "../cpp/RunAnywhereModule.h"

using namespace facebook::react;
#endif

// Include runanywhere-core C API for bridge methods
// Header is in cpp/include/, added to search paths in podspec
extern "C" {
#include "../cpp/include/runanywhere_bridge.h"
}

// Streaming audio constants (following Swift SDK's AudioCapture pattern)
static const int kMinBufferSize = 1600;  // 100ms at 16kHz
static const int kTranscriptionBufferSize = 16000;  // 1 second of audio for transcription

@implementation RunAnywhere {
#ifdef RCT_NEW_ARCH_ENABLED
    std::shared_ptr<facebook::react::RunAnywhereModule> _nativeModule;
#endif
    ra_backend_handle _backend;        // General purpose backend (ONNX for STT/TTS/VAD)
    ra_backend_handle _llamaBackend;   // LlamaCPP backend for text generation (GGUF models)
    NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *_downloadTasks;
    NSURLSession *_downloadSession;

    // Streaming audio capture
    AVAudioEngine *_audioEngine;
    AVAudioConverter *_audioConverter;
    NSMutableArray<NSNumber *> *_audioBuffer;
    BOOL _isStreamingSTT;
    int _sequenceNumber;
    NSString *_streamingLanguage;
    dispatch_queue_t _audioProcessingQueue;
    NSTimer *_transcriptionTimer;
    NSTimeInterval _lastTranscriptionTime;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _backend = nullptr;
        _llamaBackend = nullptr;
        _downloadTasks = [NSMutableDictionary new];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 300;
        config.timeoutIntervalForResource = 600;
        _downloadSession = [NSURLSession sessionWithConfiguration:config
                                                         delegate:nil
                                                    delegateQueue:[NSOperationQueue mainQueue]];

        // Initialize streaming audio capture state
        _audioEngine = nil;
        _audioConverter = nil;
        _audioBuffer = [NSMutableArray new];
        _isStreamingSTT = NO;
        _sequenceNumber = 0;
        _streamingLanguage = nil;
        _audioProcessingQueue = dispatch_queue_create("com.runanywhere.audioprocessing", DISPATCH_QUEUE_SERIAL);
        _transcriptionTimer = nil;
        _lastTranscriptionTime = 0;
    }
    return self;
}

- (void)dealloc {
    // Stop streaming if active
    [self stopStreamingSTTInternal];

    if (_llamaBackend) {
        ra_destroy(_llamaBackend);
        _llamaBackend = nullptr;
    }
    if (_backend) {
        ra_destroy(_backend);
        _backend = nullptr;
    }
}

- (NSArray<NSString *> *)supportedEvents {
    return @[
        @"onToken",
        @"onGenerationComplete",
        @"onGenerationError",
        @"onSTTPartial",
        @"onSTTFinal",
        @"onSTTError",
        @"onSTTStreamingStarted",
        @"onSTTStreamingStopped",
        @"onTTSAudio",
        @"onTTSComplete",
        @"onTTSError",
        @"onVADResult",
        @"onModelDownloadProgress",
        @"onModelDownloadComplete",
        @"onModelDownloadError",
        @"onModelLoadProgress"
    ];
}

// ============================================================================
// Helper Methods
// ============================================================================

- (NSString *)modelsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *modelsDir = [documentsDirectory stringByAppendingPathComponent:@"RunAnywhere/Models"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:modelsDir]) {
        [fm createDirectoryAtPath:modelsDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return modelsDir;
}

// ============================================================================
// Archive Extraction Methods
// ============================================================================

/// Extract a tar.bz2 archive to a destination directory
/// This is a native implementation since ra_extract_archive is not implemented in the XCFramework
- (BOOL)extractTarBz2:(NSString *)archivePath toDirectory:(NSString *)destDir error:(NSError **)outError {
    NSLog(@"[RunAnywhere] Extracting tar.bz2 archive: %@ to %@", archivePath, destDir);

    NSFileManager *fm = [NSFileManager defaultManager];

    // Create destination directory if it doesn't exist
    if (![fm fileExistsAtPath:destDir]) {
        NSError *mkdirError = nil;
        [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:&mkdirError];
        if (mkdirError) {
            NSLog(@"[RunAnywhere] Failed to create directory: %@", mkdirError);
            if (outError) *outError = mkdirError;
            return NO;
        }
    }

    // Read compressed file
    NSData *compressedData = [NSData dataWithContentsOfFile:archivePath];
    if (!compressedData || compressedData.length == 0) {
        NSLog(@"[RunAnywhere] Failed to read archive file");
        if (outError) *outError = [NSError errorWithDomain:@"RunAnywhere" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to read archive file"}];
        return NO;
    }

    NSLog(@"[RunAnywhere] Archive size: %lu bytes", (unsigned long)compressedData.length);

    // Decompress bz2 using bzlib
    NSData *tarData = [self decompressBz2:compressedData];
    if (!tarData || tarData.length == 0) {
        NSLog(@"[RunAnywhere] Failed to decompress bz2");
        if (outError) *outError = [NSError errorWithDomain:@"RunAnywhere" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to decompress bz2 data"}];
        return NO;
    }

    NSLog(@"[RunAnywhere] Decompressed tar size: %lu bytes", (unsigned long)tarData.length);

    // Extract tar archive
    BOOL success = [self extractTar:tarData toDirectory:destDir error:outError];

    if (success) {
        // List extracted contents
        NSArray *contents = [fm contentsOfDirectoryAtPath:destDir error:nil];
        NSLog(@"[RunAnywhere] Extracted contents: %@", contents);
    }

    return success;
}

/// Decompress bz2 data using bzlib
- (NSData *)decompressBz2:(NSData *)compressedData {
    if (compressedData.length < 10) {
        NSLog(@"[RunAnywhere] BZ2 data too small");
        return nil;
    }

    // Verify BZ2 header: "BZh"
    const unsigned char *bytes = (const unsigned char *)compressedData.bytes;
    if (bytes[0] != 'B' || bytes[1] != 'Z' || bytes[2] != 'h') {
        NSLog(@"[RunAnywhere] Invalid BZ2 header: %c%c%c", bytes[0], bytes[1], bytes[2]);
        return nil;
    }

    NSLog(@"[RunAnywhere] Valid BZ2 header detected");

    // Initialize bz2 stream
    bz_stream stream;
    memset(&stream, 0, sizeof(stream));

    int bzError = BZ2_bzDecompressInit(&stream, 0, 0);
    if (bzError != BZ_OK) {
        NSLog(@"[RunAnywhere] BZ2_bzDecompressInit failed: %d", bzError);
        return nil;
    }

    // Allocate output buffer - start with 10x input size, grow as needed
    NSMutableData *decompressedData = [NSMutableData dataWithCapacity:compressedData.length * 10];
    const size_t chunkSize = 1024 * 1024; // 1MB chunks
    void *outputBuffer = malloc(chunkSize);

    if (!outputBuffer) {
        BZ2_bzDecompressEnd(&stream);
        return nil;
    }

    stream.next_in = (char *)compressedData.bytes;
    stream.avail_in = (unsigned int)compressedData.length;

    do {
        stream.next_out = (char *)outputBuffer;
        stream.avail_out = (unsigned int)chunkSize;

        bzError = BZ2_bzDecompress(&stream);

        if (bzError != BZ_OK && bzError != BZ_STREAM_END) {
            NSLog(@"[RunAnywhere] BZ2_bzDecompress failed: %d", bzError);
            free(outputBuffer);
            BZ2_bzDecompressEnd(&stream);
            return nil;
        }

        size_t bytesWritten = chunkSize - stream.avail_out;
        if (bytesWritten > 0) {
            [decompressedData appendBytes:outputBuffer length:bytesWritten];
        }

    } while (bzError != BZ_STREAM_END);

    free(outputBuffer);
    BZ2_bzDecompressEnd(&stream);

    NSLog(@"[RunAnywhere] BZ2 decompression complete: %lu bytes", (unsigned long)decompressedData.length);

    return decompressedData;
}

/// Extract tar archive data to a directory
- (BOOL)extractTar:(NSData *)tarData toDirectory:(NSString *)destDir error:(NSError **)outError {
    NSFileManager *fm = [NSFileManager defaultManager];
    const unsigned char *bytes = (const unsigned char *)tarData.bytes;
    NSUInteger length = tarData.length;
    NSUInteger offset = 0;
    const NSUInteger blockSize = 512;
    int filesExtracted = 0;

    while (offset + blockSize <= length) {
        // Read 512-byte tar header
        const unsigned char *header = bytes + offset;

        // Check for end of archive (two zero blocks)
        BOOL allZero = YES;
        for (int i = 0; i < blockSize && allZero; i++) {
            if (header[i] != 0) allZero = NO;
        }
        if (allZero) {
            break;
        }

        // Parse tar header
        // Name: bytes 0-99 (null-terminated)
        char nameBuffer[101];
        memcpy(nameBuffer, header, 100);
        nameBuffer[100] = '\0';
        NSString *name = [NSString stringWithUTF8String:nameBuffer];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];

        // Check for extended header prefix (for long names)
        // Prefix: bytes 345-499
        char prefixBuffer[156];
        memcpy(prefixBuffer, header + 345, 155);
        prefixBuffer[155] = '\0';
        NSString *prefix = [NSString stringWithUTF8String:prefixBuffer];
        prefix = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];

        if (prefix.length > 0 && name.length > 0) {
            name = [NSString stringWithFormat:@"%@/%@", prefix, name];
        }

        if (name.length == 0) {
            offset += blockSize;
            continue;
        }

        // Size: bytes 124-135 (octal string)
        char sizeBuffer[13];
        memcpy(sizeBuffer, header + 124, 12);
        sizeBuffer[12] = '\0';
        NSUInteger fileSize = strtoul(sizeBuffer, NULL, 8);

        // Type flag: byte 156
        char typeFlag = (char)header[156];

        offset += blockSize;

        // Build full path
        NSString *fullPath = [destDir stringByAppendingPathComponent:name];

        // Handle based on type
        if (typeFlag == '5' || [name hasSuffix:@"/"]) {
            // Directory
            NSError *dirError = nil;
            [fm createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:&dirError];
            if (dirError) {
                NSLog(@"[RunAnywhere] Failed to create directory %@: %@", name, dirError);
            }
        } else if (typeFlag == '0' || typeFlag == '\0' || typeFlag == ' ') {
            // Regular file
            if (fileSize > 0 && offset + fileSize <= length) {
                // Create parent directory if needed
                NSString *parentDir = [fullPath stringByDeletingLastPathComponent];
                [fm createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];

                // Write file data
                NSData *fileData = [NSData dataWithBytes:bytes + offset length:fileSize];
                NSError *writeError = nil;
                BOOL written = [fileData writeToFile:fullPath options:NSDataWritingAtomic error:&writeError];
                if (!written) {
                    NSLog(@"[RunAnywhere] Failed to write file %@: %@", name, writeError);
                } else {
                    filesExtracted++;
                }
            }

            // Advance to next block boundary
            NSUInteger blocks = (fileSize + blockSize - 1) / blockSize;
            offset += blocks * blockSize;
        } else {
            // Other types (symlinks, etc.) - skip
            NSUInteger blocks = (fileSize + blockSize - 1) / blockSize;
            offset += blocks * blockSize;
        }
    }

    NSLog(@"[RunAnywhere] Tar extraction complete: %d files extracted", filesExtracted);
    return filesExtracted > 0;
}

- (NSDictionary *)getModelCatalog {
    // Hardcoded model catalog - in production this would be fetched from server
    return @{
        @"whisper-tiny-en": @{
            @"id": @"whisper-tiny-en",
            @"name": @"Whisper Tiny English",
            @"description": @"Fast English speech recognition",
            @"category": @"stt",
            @"modality": @"stt",
            @"size": @(75000000),  // ~75MB
            @"downloadUrl": @"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2",
            @"format": @"sherpa-onnx",
            @"modelType": @"whisper"
        },
        @"whisper-base-en": @{
            @"id": @"whisper-base-en",
            @"name": @"Whisper Base English",
            @"description": @"Balanced English speech recognition",
            @"category": @"stt",
            @"modality": @"stt",
            @"size": @(150000000),  // ~150MB
            @"downloadUrl": @"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.en.tar.bz2",
            @"format": @"sherpa-onnx",
            @"modelType": @"whisper"
        },
        @"silero-vad": @{
            @"id": @"silero-vad",
            @"name": @"Silero VAD",
            @"description": @"Voice Activity Detection",
            @"category": @"vad",
            @"modality": @"vad",
            @"size": @(2000000),  // ~2MB
            @"downloadUrl": @"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
            @"format": @"onnx",
            @"modelType": @"silero"
        },
        @"piper-en-us-lessac-medium": @{
            @"id": @"piper-en-us-lessac-medium",
            @"name": @"Piper TTS (US English - Medium)",
            @"description": @"High quality US English TTS voice",
            @"category": @"tts",
            @"modality": @"tts",
            @"size": @(65000000),  // ~65MB
            @"downloadUrl": @"https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
            @"format": @"sherpa-onnx",
            @"modelType": @"piper"
        },
        @"piper-en-gb-alba-medium": @{
            @"id": @"piper-en-gb-alba-medium",
            @"name": @"Piper TTS (British English)",
            @"description": @"British English TTS voice",
            @"category": @"tts",
            @"modality": @"tts",
            @"size": @(65000000),  // ~65MB
            @"downloadUrl": @"https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
            @"format": @"sherpa-onnx",
            @"modelType": @"piper"
        },
        @"qwen2-0.5b-instruct-q4": @{
            @"id": @"qwen2-0.5b-instruct-q4",
            @"name": @"Qwen2 0.5B Instruct (Q4)",
            @"description": @"Small but capable chat model for on-device inference",
            @"category": @"llm",
            @"modality": @"llm",
            @"size": @(400000000),  // ~400MB
            @"downloadUrl": @"https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_0.gguf",
            @"format": @"gguf",
            @"modelType": @"llama",
            @"contextLength": @(32768)
        },
        @"tinyllama-1.1b-chat-q4": @{
            @"id": @"tinyllama-1.1b-chat-q4",
            @"name": @"TinyLlama 1.1B Chat (Q4)",
            @"description": @"Efficient chat model optimized for mobile",
            @"category": @"llm",
            @"modality": @"llm",
            @"size": @(670000000),  // ~670MB
            @"downloadUrl": @"https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            @"format": @"gguf",
            @"modelType": @"llama",
            @"contextLength": @(2048)
        },
        @"smollm-135m-instruct-q8": @{
            @"id": @"smollm-135m-instruct-q8",
            @"name": @"SmolLM 135M Instruct (Q8)",
            @"description": @"Ultra-small model for quick responses",
            @"category": @"llm",
            @"modality": @"llm",
            @"size": @(150000000),  // ~150MB
            @"downloadUrl": @"https://huggingface.co/HuggingFaceTB/smollm-135M-instruct-v0.2-GGUF/resolve/main/smollm-135m-instruct-v0.2-q8_0.gguf",
            @"format": @"gguf",
            @"modelType": @"llama",
            @"contextLength": @(2048)
        }
    };
}

#ifdef RCT_NEW_ARCH_ENABLED

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {

    if (!_nativeModule) {
        _nativeModule = std::make_shared<facebook::react::RunAnywhereModule>(params.jsInvoker);
    }

    return _nativeModule;
}

#endif

// ============================================================================
// Bridge Methods - These work with both Old and New Architecture via NativeModules
// ============================================================================

RCT_EXPORT_METHOD(createBackend:(NSString *)name
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] createBackend called with name: %@", name);

    // Route llamacpp to _llamaBackend, others to _backend
    BOOL isLlamaCpp = [name isEqualToString:@"llamacpp"];

    if (isLlamaCpp) {
        if (_llamaBackend) {
            NSLog(@"[RunAnywhere] Destroying existing llamacpp backend");
            ra_destroy(_llamaBackend);
            _llamaBackend = nullptr;
        }

        _llamaBackend = ra_create_backend([name UTF8String]);
        NSLog(@"[RunAnywhere] LlamaCPP backend created: %@", _llamaBackend != nullptr ? @"SUCCESS" : @"FAILED");
        resolve(@(_llamaBackend != nullptr));
    } else {
        if (_backend) {
            NSLog(@"[RunAnywhere] Destroying existing backend");
            ra_destroy(_backend);
            _backend = nullptr;
        }

        _backend = ra_create_backend([name UTF8String]);
        NSLog(@"[RunAnywhere] Backend created: %@", _backend != nullptr ? @"SUCCESS" : @"FAILED");
        resolve(@(_backend != nullptr));
    }
}

RCT_EXPORT_METHOD(initialize:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] initialize called");

    // Initialize whichever backend(s) are available
    BOOL success = YES;

    if (_llamaBackend) {
        ra_result_code result = ra_initialize(_llamaBackend, configJson ? [configJson UTF8String] : nullptr);
        NSLog(@"[RunAnywhere] initialize llamacpp backend result: %d (0=SUCCESS)", result);
        success = success && (result == RA_SUCCESS);
    }

    if (_backend) {
        ra_result_code result = ra_initialize(_backend, configJson ? [configJson UTF8String] : nullptr);
        NSLog(@"[RunAnywhere] initialize onnx backend result: %d (0=SUCCESS)", result);
        success = success && (result == RA_SUCCESS);
    }

    if (!_llamaBackend && !_backend) {
        NSLog(@"[RunAnywhere] initialize: No backend available");
        resolve(@NO);
        return;
    }

    resolve(@(success));
}

RCT_EXPORT_METHOD(destroy:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_llamaBackend) {
        ra_destroy(_llamaBackend);
        _llamaBackend = nullptr;
    }
    if (_backend) {
        ra_destroy(_backend);
        _backend = nullptr;
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(isInitialized:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Check if either backend is initialized
    BOOL llamaInitialized = _llamaBackend && ra_is_initialized(_llamaBackend);
    BOOL onnxInitialized = _backend && ra_is_initialized(_backend);
    resolve(@(llamaInitialized || onnxInitialized));
}

RCT_EXPORT_METHOD(getBackendInfo:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] getBackendInfo called");

    // Return info about both backends if available
    NSMutableDictionary *backendInfo = [NSMutableDictionary new];

    if (_llamaBackend) {
        char *info = ra_get_backend_info(_llamaBackend);
        if (info) {
            NSData *data = [[NSString stringWithUTF8String:info] dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *llamaInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (llamaInfo) {
                backendInfo[@"llamacpp"] = llamaInfo;
            }
            ra_free_string(info);
        }
    }

    if (_backend) {
        char *info = ra_get_backend_info(_backend);
        if (info) {
            NSData *data = [[NSString stringWithUTF8String:info] dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *onnxInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (onnxInfo) {
                backendInfo[@"onnx"] = onnxInfo;
            }
            ra_free_string(info);
        }
    }

    if (backendInfo.count == 0) {
        NSLog(@"[RunAnywhere] getBackendInfo: No backend");
        resolve(@"{}");
        return;
    }

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:backendInfo options:0 error:&error];
    if (jsonData) {
        NSString *result = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSLog(@"[RunAnywhere] getBackendInfo: %@", result);
        resolve(result);
    } else {
        NSLog(@"[RunAnywhere] getBackendInfo: JSON serialization error");
        resolve(@"{}");
    }
}

// ============================================================================
// Text Generation Methods
// ============================================================================

RCT_EXPORT_METHOD(loadTextModel:(NSString *)path
                  configJson:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] loadTextModel called - path: %@", path);

    // Check if path exists
    BOOL pathExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSLog(@"[RunAnywhere] loadTextModel: Path exists: %@", pathExists ? @"YES" : @"NO");

    if (!pathExists) {
        NSLog(@"[RunAnywhere] loadTextModel: File does not exist at path");
        reject(@"FILE_NOT_FOUND", [NSString stringWithFormat:@"Model file not found at path: %@", path], nil);
        return;
    }

    // Get file info
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *fileSize = attrs[NSFileSize];
    NSLog(@"[RunAnywhere] loadTextModel: File size: %@ bytes", fileSize);

    // Determine backend type based on file extension
    NSString *ext = [[path pathExtension] lowercaseString];
    BOOL isGGUF = [ext isEqualToString:@"gguf"] || [ext isEqualToString:@"ggml"];
    NSLog(@"[RunAnywhere] loadTextModel: Extension: %@, isGGUF: %@", ext, isGGUF ? @"YES" : @"NO");

    // Check for corrupted model files (minimum size check)
    // GGUF models should be at least 1MB - anything smaller is likely corrupted or incomplete download
    static const long long MIN_GGUF_SIZE = 1 * 1024 * 1024;  // 1MB minimum
    if (isGGUF && [fileSize longLongValue] < MIN_GGUF_SIZE) {
        NSLog(@"[RunAnywhere] loadTextModel: File appears corrupted (size: %@ bytes, minimum: %lld bytes)", fileSize, MIN_GGUF_SIZE);
        reject(@"MODEL_CORRUPTED",
               [NSString stringWithFormat:@"Model file appears corrupted or incomplete (size: %@ bytes). Please delete and re-download the model.", fileSize],
               nil);
        return;
    }

    // For GGUF models, use the llamacpp backend
    if (isGGUF) {
        NSLog(@"[RunAnywhere] loadTextModel: Creating/using LlamaCPP backend for GGUF model");

        // Create llamacpp backend if not already created
        if (!_llamaBackend) {
            NSLog(@"[RunAnywhere] loadTextModel: Creating new LlamaCPP backend");
            _llamaBackend = ra_create_backend("llamacpp");

            if (!_llamaBackend) {
                NSLog(@"[RunAnywhere] loadTextModel: Failed to create LlamaCPP backend");
                reject(@"BACKEND_CREATE_FAILED", @"Failed to create LlamaCPP backend for GGUF models", nil);
                return;
            }

            // Initialize the backend
            ra_result_code initResult = ra_initialize(_llamaBackend, nullptr);
            NSLog(@"[RunAnywhere] loadTextModel: LlamaCPP backend init result: %d (0=SUCCESS)", initResult);

            if (initResult != RA_SUCCESS) {
                const char *error = ra_get_last_error();
                NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
                NSLog(@"[RunAnywhere] loadTextModel: LlamaCPP init error: %@", errorMsg);

                ra_destroy(_llamaBackend);
                _llamaBackend = nullptr;

                reject(@"BACKEND_INIT_FAILED", [NSString stringWithFormat:@"Failed to initialize LlamaCPP backend: %@", errorMsg], nil);
                return;
            }
        }

        // Load model using llamacpp backend
        ra_result_code result = ra_text_load_model(
            _llamaBackend,
            [path UTF8String],
            configJson ? [configJson UTF8String] : nullptr
        );

        NSLog(@"[RunAnywhere] loadTextModel result (LlamaCPP): %d (0=SUCCESS)", result);

        if (result != RA_SUCCESS) {
            const char *error = ra_get_last_error();
            NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
            NSLog(@"[RunAnywhere] loadTextModel error: %@", errorMsg);

            NSString *userFacingError;
            if (result == -2) {  // RA_ERROR_MODEL_LOAD_FAILED
                userFacingError = [NSString stringWithFormat:@"Failed to load GGUF model. This may be due to architecture limitations (e.g., simulator without Metal). Try running on a physical device. Details: %@", errorMsg];
            } else {
                userFacingError = errorMsg;
            }

            reject(@"MODEL_LOAD_FAILED", userFacingError, nil);
            return;
        }

        resolve(@YES);
        return;
    }

    // For non-GGUF models, use the general backend
    if (!_backend) {
        NSLog(@"[RunAnywhere] loadTextModel: No general backend available for non-GGUF model");
        reject(@"NO_BACKEND", @"Backend not initialized. Please call createBackend first.", nil);
        return;
    }

    ra_result_code result = ra_text_load_model(
        _backend,
        [path UTF8String],
        configJson ? [configJson UTF8String] : nullptr
    );

    NSLog(@"[RunAnywhere] loadTextModel result: %d (0=SUCCESS)", result);

    if (result != RA_SUCCESS) {
        const char *error = ra_get_last_error();
        NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
        NSLog(@"[RunAnywhere] loadTextModel error: %@", errorMsg);
        reject(@"MODEL_LOAD_FAILED", errorMsg, nil);
        return;
    }

    resolve(@YES);
}

RCT_EXPORT_METHOD(isTextModelLoaded:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Check llamacpp backend first (GGUF models)
    if (_llamaBackend && ra_text_is_model_loaded(_llamaBackend)) {
        resolve(@YES);
        return;
    }
    // Check general backend
    if (_backend && ra_text_is_model_loaded(_backend)) {
        resolve(@YES);
        return;
    }
    resolve(@NO);
}

RCT_EXPORT_METHOD(unloadTextModel:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    BOOL success = YES;

    // Unload from llamacpp backend if loaded
    if (_llamaBackend && ra_text_is_model_loaded(_llamaBackend)) {
        success = ra_text_unload_model(_llamaBackend) == RA_SUCCESS;
    }

    // Unload from general backend if loaded
    if (_backend && ra_text_is_model_loaded(_backend)) {
        success = ra_text_unload_model(_backend) == RA_SUCCESS && success;
    }

    resolve(@(success));
}

RCT_EXPORT_METHOD(generate:(NSString *)prompt
                  systemPrompt:(NSString *)systemPrompt
                  maxTokens:(int)maxTokens
                  temperature:(double)temperature
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] generate called - prompt: %.50s..., maxTokens: %d, temp: %f", [prompt UTF8String], maxTokens, temperature);

    // Determine which backend to use
    ra_backend_handle activeBackend = nullptr;
    NSString *backendType = @"none";

    // Check llamacpp backend first (GGUF models)
    if (_llamaBackend && ra_text_is_model_loaded(_llamaBackend)) {
        activeBackend = _llamaBackend;
        backendType = @"llamacpp";
        NSLog(@"[RunAnywhere] generate: Using LlamaCPP backend");
    }
    // Check general backend
    else if (_backend && ra_text_is_model_loaded(_backend)) {
        activeBackend = _backend;
        backendType = @"general";
        NSLog(@"[RunAnywhere] generate: Using general backend");
    }

    if (!activeBackend) {
        NSLog(@"[RunAnywhere] generate: No backend with loaded model available");
        resolve(@"{\"error\": \"No text model loaded. Please load a model first.\"}");
        return;
    }

    char *resultJson = nullptr;
    NSLog(@"[RunAnywhere] generate: Calling ra_text_generate on %@ backend...", backendType);
    ra_result_code result = ra_text_generate(
        activeBackend,
        [prompt UTF8String],
        systemPrompt ? [systemPrompt UTF8String] : nullptr,
        maxTokens,
        (float)temperature,
        &resultJson
    );

    NSLog(@"[RunAnywhere] generate: Result code: %d (0=SUCCESS)", result);

    if (result != RA_SUCCESS || !resultJson) {
        const char *error = ra_get_last_error();
        NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
        NSLog(@"[RunAnywhere] generate: Error - %@", errorMsg);
        resolve([NSString stringWithFormat:@"{\"error\": \"%@\"}", errorMsg]);
        return;
    }

    NSString *resultStr = [NSString stringWithUTF8String:resultJson];
    NSLog(@"[RunAnywhere] generate: Success - response length: %lu", (unsigned long)resultStr.length);
    ra_free_string(resultJson);
    resolve(resultStr);
}

RCT_EXPORT_METHOD(generateStream:(NSString *)prompt
                  systemPrompt:(NSString *)systemPrompt
                  maxTokens:(int)maxTokens
                  temperature:(double)temperature) {
    // Determine which backend to use
    ra_backend_handle activeBackend = nullptr;

    // Check llamacpp backend first (GGUF models)
    if (_llamaBackend && ra_text_is_model_loaded(_llamaBackend)) {
        activeBackend = _llamaBackend;
    }
    // Check general backend
    else if (_backend && ra_text_is_model_loaded(_backend)) {
        activeBackend = _backend;
    }

    if (!activeBackend) {
        [self sendEventWithName:@"onGenerationError"
                           body:@{@"error": @"No text model loaded"}];
        return;
    }

    // For now, use non-streaming and send complete result
    // TODO: Implement actual streaming with callback
    char *resultJson = nullptr;
    ra_result_code result = ra_text_generate(
        activeBackend,
        [prompt UTF8String],
        systemPrompt ? [systemPrompt UTF8String] : nullptr,
        maxTokens,
        (float)temperature,
        &resultJson
    );

    if (result != RA_SUCCESS || !resultJson) {
        const char *error = ra_get_last_error();
        NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
        [self sendEventWithName:@"onGenerationError" body:@{@"error": errorMsg}];
        return;
    }

    NSString *resultStr = [NSString stringWithUTF8String:resultJson];
    ra_free_string(resultJson);

    // Parse and emit tokens from result
    NSData *data = [resultStr dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *jsonResult = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSString *text = jsonResult[@"text"];
    if (text) {
        [self sendEventWithName:@"onToken" body:@{@"token": text}];
    }
    [self sendEventWithName:@"onGenerationComplete" body:jsonResult ?: @{}];
}

RCT_EXPORT_METHOD(cancelGeneration) {
    // Cancel on both backends
    if (_llamaBackend) {
        ra_text_cancel(_llamaBackend);
    }
    if (_backend) {
        ra_text_cancel(_backend);
    }
}

// ============================================================================
// Capability Query
// ============================================================================

RCT_EXPORT_METHOD(supportsCapability:(int)capability
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Check capability across both backends
    BOOL supported = NO;
    if (_backend) {
        supported = ra_supports_capability(_backend, (ra_capability_type)capability);
    }
    if (!supported && _llamaBackend) {
        supported = ra_supports_capability(_llamaBackend, (ra_capability_type)capability);
    }
    resolve(@(supported));
}

RCT_EXPORT_METHOD(getCapabilities:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSMutableSet *capabilitiesSet = [NSMutableSet new];

    // Collect capabilities from both backends
    if (_backend) {
        ra_capability_type caps[10];
        int count = ra_get_capabilities(_backend, caps, 10);
        for (int i = 0; i < count; i++) {
            [capabilitiesSet addObject:@(caps[i])];
        }
    }

    if (_llamaBackend) {
        ra_capability_type caps[10];
        int count = ra_get_capabilities(_llamaBackend, caps, 10);
        for (int i = 0; i < count; i++) {
            [capabilitiesSet addObject:@(caps[i])];
        }
    }

    resolve([capabilitiesSet allObjects]);
}

RCT_EXPORT_METHOD(getDeviceType:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Return device type from any available backend
    ra_backend_handle backend = _backend ?: _llamaBackend;
    if (!backend) {
        resolve(@99); // RA_DEVICE_UNKNOWN
        return;
    }
    resolve(@(ra_get_device(backend)));
}

RCT_EXPORT_METHOD(getMemoryUsage:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    // Sum memory usage from both backends
    size_t totalMemory = 0;
    if (_backend) {
        totalMemory += ra_get_memory_usage(_backend);
    }
    if (_llamaBackend) {
        totalMemory += ra_get_memory_usage(_llamaBackend);
    }
    resolve(@(totalMemory));
}

// ============================================================================
// STT Methods
// ============================================================================

RCT_EXPORT_METHOD(loadSTTModel:(NSString *)path
                  modelType:(NSString *)modelType
                  configJson:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] loadSTTModel called - path: %@, type: %@", path, modelType);

    // Create ONNX backend for STT if not already created
    if (!_backend) {
        NSLog(@"[RunAnywhere] loadSTTModel: Creating ONNX backend for STT");
        _backend = ra_create_backend("onnx");

        if (!_backend) {
            NSLog(@"[RunAnywhere] loadSTTModel: Failed to create ONNX backend");
            reject(@"BACKEND_CREATE_FAILED", @"Failed to create ONNX backend for STT", nil);
            return;
        }

        ra_result_code initResult = ra_initialize(_backend, nullptr);
        NSLog(@"[RunAnywhere] loadSTTModel: ONNX backend init result: %d (0=SUCCESS)", initResult);

        if (initResult != RA_SUCCESS) {
            const char *error = ra_get_last_error();
            NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
            NSLog(@"[RunAnywhere] loadSTTModel: ONNX init error: %@", errorMsg);

            ra_destroy(_backend);
            _backend = nullptr;

            reject(@"BACKEND_INIT_FAILED", [NSString stringWithFormat:@"Failed to initialize ONNX backend: %@", errorMsg], nil);
            return;
        }
    }

    // Check if path exists
    BOOL pathExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSLog(@"[RunAnywhere] loadSTTModel: Path exists: %@", pathExists ? @"YES" : @"NO");

    if (!pathExists) {
        NSLog(@"[RunAnywhere] loadSTTModel: Path does not exist!");
        // Try to list contents of parent directory
        NSString *parentDir = [path stringByDeletingLastPathComponent];
        NSError *listError = nil;
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:parentDir error:&listError];
        if (contents) {
            NSLog(@"[RunAnywhere] loadSTTModel: Parent dir (%@) contents: %@", parentDir, contents);
        } else {
            NSLog(@"[RunAnywhere] loadSTTModel: Could not list parent dir: %@", listError);
        }
    }

    ra_result_code result = ra_stt_load_model(
        _backend,
        [path UTF8String],
        [modelType UTF8String],
        configJson ? [configJson UTF8String] : nullptr
    );

    NSLog(@"[RunAnywhere] loadSTTModel result: %d (0=SUCCESS)", result);

    if (result != RA_SUCCESS) {
        const char *error = ra_get_last_error();
        NSLog(@"[RunAnywhere] loadSTTModel error: %s", error ? error : "NULL");
    }

    resolve(@(result == RA_SUCCESS));
}

RCT_EXPORT_METHOD(isSTTModelLoaded:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_stt_is_model_loaded(_backend)));
}

RCT_EXPORT_METHOD(unloadSTTModel:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_stt_unload_model(_backend) == RA_SUCCESS));
}

RCT_EXPORT_METHOD(transcribe:(NSString *)audioBase64
                  sampleRate:(int)sampleRate
                  language:(NSString *)language
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@"{\"error\": \"Backend not initialized\"}");
        return;
    }

    // Decode base64 audio
    NSData *audioData = [[NSData alloc] initWithBase64EncodedString:audioBase64 options:0];
    if (!audioData) {
        resolve(@"{\"error\": \"Failed to decode audio\"}");
        return;
    }

    size_t numSamples = audioData.length / sizeof(float);
    const float *samples = (const float *)audioData.bytes;

    char *resultJson = nullptr;
    ra_result_code result = ra_stt_transcribe(
        _backend,
        samples,
        numSamples,
        sampleRate,
        language ? [language UTF8String] : nullptr,
        &resultJson
    );

    if (result != RA_SUCCESS || !resultJson) {
        resolve(@"{\"error\": \"Transcription failed\"}");
        return;
    }

    NSString *resultStr = [NSString stringWithUTF8String:resultJson];
    ra_free_string(resultJson);
    resolve(resultStr);
}

RCT_EXPORT_METHOD(transcribeFile:(NSString *)filePath
                  language:(NSString *)language
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] transcribeFile called with path: %@", filePath);

    if (!_backend) {
        resolve(@"{\"error\": \"Backend not initialized\"}");
        return;
    }

    // Remove file:// prefix if present
    NSString *cleanPath = filePath;
    if ([filePath hasPrefix:@"file://"]) {
        cleanPath = [filePath substringFromIndex:7];
    }

    // Check file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:cleanPath]) {
        NSLog(@"[RunAnywhere] transcribeFile: File not found at path: %@", cleanPath);
        resolve(@"{\"error\": \"Audio file not found\"}");
        return;
    }

    // Read audio file and convert to float samples
    NSURL *fileURL = [NSURL fileURLWithPath:cleanPath];
    NSError *error = nil;

    // Use AVAudioFile to read and convert audio
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
    if (error || !audioFile) {
        NSLog(@"[RunAnywhere] transcribeFile: Failed to open audio file: %@", error);
        resolve([NSString stringWithFormat:@"{\"error\": \"Failed to open audio file: %@\"}", error.localizedDescription]);
        return;
    }

    AVAudioFormat *inputFormat = audioFile.processingFormat;
    NSLog(@"[RunAnywhere] transcribeFile: Input format - sampleRate: %.0f, channels: %d",
          inputFormat.sampleRate, (int)inputFormat.channelCount);

    // Create output format: mono, 16kHz, float32
    AVAudioFormat *outputFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                   sampleRate:16000
                                                                     channels:1
                                                                  interleaved:NO];

    // Create converter
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inputFormat toFormat:outputFormat];
    if (!converter) {
        NSLog(@"[RunAnywhere] transcribeFile: Failed to create audio converter");
        resolve(@"{\"error\": \"Failed to create audio format converter\"}");
        return;
    }

    // Calculate output buffer size
    AVAudioFrameCount inputFrameCount = (AVAudioFrameCount)audioFile.length;
    double ratio = 16000.0 / inputFormat.sampleRate;
    AVAudioFrameCount outputFrameCount = (AVAudioFrameCount)(inputFrameCount * ratio) + 1024;

    // Read input audio
    AVAudioPCMBuffer *inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFormat
                                                                  frameCapacity:inputFrameCount];
    if (![audioFile readIntoBuffer:inputBuffer error:&error] || error) {
        NSLog(@"[RunAnywhere] transcribeFile: Failed to read audio file: %@", error);
        resolve([NSString stringWithFormat:@"{\"error\": \"Failed to read audio file: %@\"}", error.localizedDescription]);
        return;
    }

    // Create output buffer
    AVAudioPCMBuffer *outputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat
                                                                   frameCapacity:outputFrameCount];

    // Convert audio
    __block BOOL inputDone = NO;
    AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
        if (inputDone) {
            *outStatus = AVAudioConverterInputStatus_EndOfStream;
            return nil;
        }
        inputDone = YES;
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return inputBuffer;
    };

    NSError *convertError = nil;
    AVAudioConverterOutputStatus status = [converter convertToBuffer:outputBuffer error:&convertError withInputFromBlock:inputBlock];

    if (status == AVAudioConverterOutputStatus_Error || convertError) {
        NSLog(@"[RunAnywhere] transcribeFile: Audio conversion failed: %@", convertError);
        resolve([NSString stringWithFormat:@"{\"error\": \"Audio conversion failed: %@\"}", convertError.localizedDescription]);
        return;
    }

    // Get float samples
    const float *samples = outputBuffer.floatChannelData[0];
    size_t numSamples = outputBuffer.frameLength;

    NSLog(@"[RunAnywhere] transcribeFile: Converted %zu samples at 16kHz (%.2f seconds)",
          numSamples, (double)numSamples / 16000.0);

    // Perform transcription
    char *resultJson = nullptr;
    ra_result_code result = ra_stt_transcribe(
        _backend,
        samples,
        numSamples,
        16000,
        language ? [language UTF8String] : nullptr,
        &resultJson
    );

    if (result != RA_SUCCESS || !resultJson) {
        const char *error = ra_get_last_error();
        NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown transcription error";
        NSLog(@"[RunAnywhere] transcribeFile: Transcription failed: %@", errorMsg);
        resolve([NSString stringWithFormat:@"{\"error\": \"Transcription failed: %@\"}", errorMsg]);
        return;
    }

    NSString *resultStr = [NSString stringWithUTF8String:resultJson];
    ra_free_string(resultJson);

    NSLog(@"[RunAnywhere] transcribeFile: Success - result: %@", resultStr);
    resolve(resultStr);
}

// ============================================================================
// Streaming STT Methods (AVAudioEngine-based, matching Swift SDK pattern)
// ============================================================================

/**
 * Start streaming speech-to-text transcription using AVAudioEngine
 * This follows the Swift SDK's AudioCapture pattern for real-time audio capture
 */
RCT_EXPORT_METHOD(startStreamingSTT:(NSString *)language
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] startStreamingSTT called - language: %@", language);

    // Check if STT model is loaded
    if (!_backend || !ra_stt_is_model_loaded(_backend)) {
        NSLog(@"[RunAnywhere] startStreamingSTT: STT model not loaded");
        reject(@"MODEL_NOT_LOADED", @"STT model not loaded. Please load a model first.", nil);
        return;
    }

    // Check if already streaming
    if (_isStreamingSTT) {
        NSLog(@"[RunAnywhere] startStreamingSTT: Already streaming");
        reject(@"ALREADY_STREAMING", @"Streaming STT is already active", nil);
        return;
    }

    _streamingLanguage = language;
    _sequenceNumber = 0;
    [_audioBuffer removeAllObjects];
    _lastTranscriptionTime = [[NSDate date] timeIntervalSince1970];

    // Start audio engine on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        BOOL started = [self startAudioEngineWithError:&error];

        if (!started) {
            NSLog(@"[RunAnywhere] startStreamingSTT: Failed to start audio engine: %@", error);
            reject(@"AUDIO_ENGINE_ERROR", error.localizedDescription ?: @"Failed to start audio engine", nil);
            return;
        }

        self->_isStreamingSTT = YES;
        NSLog(@"[RunAnywhere] startStreamingSTT: Audio engine started successfully");

        // Send streaming started event
        [self sendEventWithName:@"onSTTStreamingStarted" body:@{@"status": @"started"}];

        resolve(@YES);
    });
}

/**
 * Stop streaming speech-to-text transcription
 */
RCT_EXPORT_METHOD(stopStreamingSTT:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] stopStreamingSTT called");

    if (!_isStreamingSTT) {
        NSLog(@"[RunAnywhere] stopStreamingSTT: Not currently streaming");
        resolve(@YES);
        return;
    }

    // Stop on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopStreamingSTTInternal];

        // Send streaming stopped event
        [self sendEventWithName:@"onSTTStreamingStopped" body:@{@"status": @"stopped"}];

        resolve(@YES);
    });
}

/**
 * Check if streaming STT is currently active
 */
RCT_EXPORT_METHOD(isStreamingSTT:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(_isStreamingSTT));
}

// MARK: - Internal Streaming Methods

- (void)stopStreamingSTTInternal {
    NSLog(@"[RunAnywhere] stopStreamingSTTInternal");

    _isStreamingSTT = NO;

    // Stop transcription timer
    if (_transcriptionTimer) {
        [_transcriptionTimer invalidate];
        _transcriptionTimer = nil;
    }

    // Stop audio engine
    [self stopAudioEngine];

    // Process any remaining audio buffer
    if (_audioBuffer.count >= kMinBufferSize) {
        [self transcribeAccumulatedAudio:YES];
    }

    [_audioBuffer removeAllObjects];
    _streamingLanguage = nil;
}

- (BOOL)startAudioEngineWithError:(NSError **)error {
    NSLog(@"[RunAnywhere] startAudioEngineWithError");

    // Configure audio session for voice assistant (recording + playback)
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    NSError *sessionError = nil;
    // Use .voiceChat mode with duckOthers for echo cancellation (matching Swift SDK)
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                         mode:AVAudioSessionModeVoiceChat
                      options:AVAudioSessionCategoryOptionAllowBluetooth |
                              AVAudioSessionCategoryOptionDuckOthers |
                              AVAudioSessionCategoryOptionDefaultToSpeaker
                        error:&sessionError];

    if (sessionError) {
        NSLog(@"[RunAnywhere] Failed to set audio session category: %@", sessionError);
        if (error) *error = sessionError;
        return NO;
    }

    [audioSession setActive:YES error:&sessionError];
    if (sessionError) {
        NSLog(@"[RunAnywhere] Failed to activate audio session: %@", sessionError);
        if (error) *error = sessionError;
        return NO;
    }

    // Create audio engine
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *inputNode = [_audioEngine inputNode];
    AVAudioFormat *inputFormat = [inputNode outputFormatForBus:0];

    NSLog(@"[RunAnywhere] Input format: sampleRate=%f, channels=%u",
          inputFormat.sampleRate, (unsigned int)inputFormat.channelCount);

    // Create 16kHz mono format for STT (matching Swift SDK)
    AVAudioFormat *outputFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                                   sampleRate:16000
                                                                     channels:1
                                                                  interleaved:NO];

    // Create converter if needed
    BOOL needsConversion = inputFormat.sampleRate != outputFormat.sampleRate ||
                          inputFormat.channelCount != outputFormat.channelCount;

    if (needsConversion) {
        _audioConverter = [[AVAudioConverter alloc] initFromFormat:inputFormat toFormat:outputFormat];
        if (!_audioConverter) {
            NSLog(@"[RunAnywhere] Failed to create audio converter");
            if (error) {
                *error = [NSError errorWithDomain:@"RunAnywhere"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to create audio converter"}];
            }
            return NO;
        }
    }

    // Install tap on input node
    __weak RunAnywhere *weakSelf = self;
    [inputNode installTapOnBus:0
                    bufferSize:1024
                        format:inputFormat
                         block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [weakSelf processAudioBuffer:buffer inputFormat:inputFormat outputFormat:outputFormat];
    }];

    // Start audio engine
    NSError *startError = nil;
    [_audioEngine startAndReturnError:&startError];
    if (startError) {
        NSLog(@"[RunAnywhere] Failed to start audio engine: %@", startError);
        [inputNode removeTapOnBus:0];
        _audioEngine = nil;
        _audioConverter = nil;
        if (error) *error = startError;
        return NO;
    }

    // Start transcription timer (transcribe every ~1 second when we have enough audio)
    _transcriptionTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                           target:self
                                                         selector:@selector(transcriptionTimerFired:)
                                                         userInfo:nil
                                                          repeats:YES];

    NSLog(@"[RunAnywhere] Audio engine started - capturing at 16kHz mono");
    return YES;
}

- (void)stopAudioEngine {
    NSLog(@"[RunAnywhere] stopAudioEngine");

    if (_audioEngine) {
        AVAudioInputNode *inputNode = [_audioEngine inputNode];
        [inputNode removeTapOnBus:0];
        [_audioEngine stop];
        _audioEngine = nil;
    }

    _audioConverter = nil;

    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:NO error:&error];
    if (error) {
        NSLog(@"[RunAnywhere] Failed to deactivate audio session: %@", error);
    }
}

- (void)processAudioBuffer:(AVAudioPCMBuffer *)buffer
               inputFormat:(AVAudioFormat *)inputFormat
              outputFormat:(AVAudioFormat *)outputFormat {

    if (!_isStreamingSTT) return;

    AVAudioPCMBuffer *processedBuffer = buffer;

    // Convert to 16kHz mono if needed
    if (_audioConverter) {
        AVAudioFrameCount capacity = (AVAudioFrameCount)(outputFormat.sampleRate * buffer.frameLength / inputFormat.sampleRate);
        AVAudioPCMBuffer *convertedBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat
                                                                          frameCapacity:capacity];
        if (!convertedBuffer) return;

        NSError *conversionError = nil;
        AVAudioConverterInputBlock inputBlock = ^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
            *outStatus = AVAudioConverterInputStatus_HaveData;
            return buffer;
        };

        [_audioConverter convertToBuffer:convertedBuffer error:&conversionError withInputFromBlock:inputBlock];

        if (conversionError) {
            NSLog(@"[RunAnywhere] Audio conversion error: %@", conversionError);
            return;
        }

        processedBuffer = convertedBuffer;
    }

    // Convert buffer to float array and add to audio buffer
    float *channelData = processedBuffer.floatChannelData[0];
    AVAudioFrameCount frameLength = processedBuffer.frameLength;

    dispatch_async(_audioProcessingQueue, ^{
        for (AVAudioFrameCount i = 0; i < frameLength; i++) {
            [self->_audioBuffer addObject:@(channelData[i])];
        }
    });
}

- (void)transcriptionTimerFired:(NSTimer *)timer {
    if (!_isStreamingSTT) return;

    dispatch_async(_audioProcessingQueue, ^{
        // Check if we have enough audio (at least 1 second = 16000 samples)
        if (self->_audioBuffer.count >= kTranscriptionBufferSize) {
            [self transcribeAccumulatedAudio:NO];
        }
    });
}

- (void)transcribeAccumulatedAudio:(BOOL)isFinal {
    if (_audioBuffer.count < kMinBufferSize) return;

    NSLog(@"[RunAnywhere] transcribeAccumulatedAudio - samples: %lu, isFinal: %d",
          (unsigned long)_audioBuffer.count, isFinal);

    // Convert NSArray to float array
    NSUInteger sampleCount = _audioBuffer.count;
    float *samples = (float *)malloc(sampleCount * sizeof(float));
    if (!samples) return;

    for (NSUInteger i = 0; i < sampleCount; i++) {
        samples[i] = [_audioBuffer[i] floatValue];
    }

    // Clear buffer
    [_audioBuffer removeAllObjects];

    // Transcribe on background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        const char *lang = self->_streamingLanguage ? [self->_streamingLanguage UTF8String] : "en";

        // Use ra_stt_transcribe from runanywhere-core bridge API
        char *resultJson = NULL;
        ra_result_code result_code = ra_stt_transcribe(
            self->_backend,
            samples,
            sampleCount,
            16000,  // sample rate
            lang,
            &resultJson
        );

        free(samples);

        if (result_code != RA_SUCCESS || !resultJson) {
            const char *error = ra_get_last_error();
            NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown transcription error";
            NSLog(@"[RunAnywhere] Streaming transcription error: %@", errorMsg);

            dispatch_async(dispatch_get_main_queue(), ^{
                [self sendEventWithName:@"onSTTError" body:@{@"error": errorMsg}];
            });
            return;
        }

        NSString *resultStr = [NSString stringWithUTF8String:resultJson];
        ra_free_string(resultJson);

        NSLog(@"[RunAnywhere] Streaming transcription result: %@", resultStr);

        // Parse result and send appropriate event
        NSData *jsonData = [resultStr dataUsingEncoding:NSUTF8StringEncoding];
        NSError *parseError = nil;
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];

        if (parseError || !result) {
            NSLog(@"[RunAnywhere] Failed to parse transcription result: %@", parseError);
            return;
        }

        NSString *text = result[@"text"];
        if (text && text.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *eventName = isFinal ? @"onSTTFinal" : @"onSTTPartial";
                [self sendEventWithName:eventName body:@{
                    @"text": text,
                    @"confidence": result[@"confidence"] ?: @(0.0),
                    @"isFinal": @(isFinal),
                    @"sequenceNumber": @(self->_sequenceNumber++)
                }];
            });
        }
    });
}

// ============================================================================
// TTS Methods
// ============================================================================

RCT_EXPORT_METHOD(loadTTSModel:(NSString *)path
                  modelType:(NSString *)modelType
                  configJson:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] loadTTSModel called - path: %@, type: %@", path, modelType);

    // Create ONNX backend for TTS if not already created
    if (!_backend) {
        NSLog(@"[RunAnywhere] loadTTSModel: Creating ONNX backend for TTS");
        _backend = ra_create_backend("onnx");

        if (!_backend) {
            NSLog(@"[RunAnywhere] loadTTSModel: Failed to create ONNX backend");
            reject(@"BACKEND_CREATE_FAILED", @"Failed to create ONNX backend for TTS", nil);
            return;
        }

        ra_result_code initResult = ra_initialize(_backend, nullptr);
        NSLog(@"[RunAnywhere] loadTTSModel: ONNX backend init result: %d (0=SUCCESS)", initResult);

        if (initResult != RA_SUCCESS) {
            const char *error = ra_get_last_error();
            NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
            NSLog(@"[RunAnywhere] loadTTSModel: ONNX init error: %@", errorMsg);

            ra_destroy(_backend);
            _backend = nullptr;

            reject(@"BACKEND_INIT_FAILED", [NSString stringWithFormat:@"Failed to initialize ONNX backend: %@", errorMsg], nil);
            return;
        }
    }

    // Check if path exists
    BOOL pathExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSLog(@"[RunAnywhere] loadTTSModel: Path exists: %@", pathExists ? @"YES" : @"NO");

    // Always use "vits" model type for Sherpa-ONNX TTS (per Swift SDK pattern)
    // The modelType parameter from JS is ignored
    NSLog(@"[RunAnywhere] loadTTSModel: Using hardcoded model type 'vits' (Sherpa-ONNX pattern)");

    ra_result_code result = ra_tts_load_model(
        _backend,
        [path UTF8String],
        "vits",  // Hardcoded per Swift SDK - Sherpa-ONNX TTS uses VITS architecture
        configJson ? [configJson UTF8String] : nullptr
    );

    NSLog(@"[RunAnywhere] loadTTSModel result: %d (0=SUCCESS)", result);

    if (result != RA_SUCCESS) {
        const char *error = ra_get_last_error();
        NSLog(@"[RunAnywhere] loadTTSModel error: %s", error ? error : "NULL");
    }

    resolve(@(result == RA_SUCCESS));
}

RCT_EXPORT_METHOD(isTTSModelLoaded:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_tts_is_model_loaded(_backend)));
}

RCT_EXPORT_METHOD(unloadTTSModel:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_tts_unload_model(_backend) == RA_SUCCESS));
}

RCT_EXPORT_METHOD(synthesize:(NSString *)text
                  voiceId:(NSString *)voiceId
                  speedRate:(double)speedRate
                  pitchShift:(double)pitchShift
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@"{\"error\": \"Backend not initialized\"}");
        return;
    }

    float *audioSamples = nullptr;
    size_t numSamples = 0;
    int sampleRate = 0;

    ra_result_code result = ra_tts_synthesize(
        _backend,
        [text UTF8String],
        voiceId ? [voiceId UTF8String] : nullptr,
        (float)speedRate,
        (float)pitchShift,
        &audioSamples,
        &numSamples,
        &sampleRate
    );

    if (result != RA_SUCCESS || !audioSamples) {
        resolve(@"{\"error\": \"Synthesis failed\"}");
        return;
    }

    // Encode audio to base64
    NSData *audioData = [NSData dataWithBytes:audioSamples length:numSamples * sizeof(float)];
    NSString *audioBase64 = [audioData base64EncodedStringWithOptions:0];
    ra_free_audio(audioSamples);

    NSString *resultJson = [NSString stringWithFormat:@"{\"audio\": \"%@\", \"sampleRate\": %d, \"numSamples\": %zu}",
                           audioBase64, sampleRate, numSamples];
    resolve(resultJson);
}

RCT_EXPORT_METHOD(getTTSVoices:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@"[]");
        return;
    }

    char *voicesJson = ra_tts_get_voices(_backend);
    if (voicesJson) {
        NSString *result = [NSString stringWithUTF8String:voicesJson];
        ra_free_string(voicesJson);
        resolve(result);
    } else {
        resolve(@"[]");
    }
}

RCT_EXPORT_METHOD(supportsTTSStreaming:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_tts_supports_streaming(_backend)));
}

RCT_EXPORT_METHOD(cancelTTS) {
    if (_backend) {
        ra_tts_cancel(_backend);
    }
}

// ============================================================================
// VAD Methods
// ============================================================================

RCT_EXPORT_METHOD(loadVADModel:(NSString *)path
                  configJson:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] loadVADModel called - path: %@", path);

    // Create ONNX backend for VAD if not already created
    if (!_backend) {
        NSLog(@"[RunAnywhere] loadVADModel: Creating ONNX backend for VAD");
        _backend = ra_create_backend("onnx");

        if (!_backend) {
            NSLog(@"[RunAnywhere] loadVADModel: Failed to create ONNX backend");
            reject(@"BACKEND_CREATE_FAILED", @"Failed to create ONNX backend for VAD", nil);
            return;
        }

        ra_result_code initResult = ra_initialize(_backend, nullptr);
        NSLog(@"[RunAnywhere] loadVADModel: ONNX backend init result: %d (0=SUCCESS)", initResult);

        if (initResult != RA_SUCCESS) {
            const char *error = ra_get_last_error();
            NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
            NSLog(@"[RunAnywhere] loadVADModel: ONNX init error: %@", errorMsg);

            ra_destroy(_backend);
            _backend = nullptr;

            reject(@"BACKEND_INIT_FAILED", [NSString stringWithFormat:@"Failed to initialize ONNX backend: %@", errorMsg], nil);
            return;
        }
    }

    // Check if path exists
    BOOL pathExists = [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSLog(@"[RunAnywhere] loadVADModel: Path exists: %@", pathExists ? @"YES" : @"NO");

    ra_result_code result = ra_vad_load_model(
        _backend,
        [path UTF8String],
        configJson ? [configJson UTF8String] : nullptr
    );

    NSLog(@"[RunAnywhere] loadVADModel result: %d (0=SUCCESS)", result);

    if (result != RA_SUCCESS) {
        const char *error = ra_get_last_error();
        NSLog(@"[RunAnywhere] loadVADModel error: %s", error ? error : "NULL");
    }

    resolve(@(result == RA_SUCCESS));
}

RCT_EXPORT_METHOD(isVADModelLoaded:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_vad_is_model_loaded(_backend)));
}

RCT_EXPORT_METHOD(processVAD:(NSString *)audioBase64
                  sampleRate:(int)sampleRate
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@"{\"isSpeech\": false, \"probability\": 0}");
        return;
    }

    // Decode base64 audio
    NSData *audioData = [[NSData alloc] initWithBase64EncodedString:audioBase64 options:0];
    if (!audioData) {
        resolve(@"{\"isSpeech\": false, \"probability\": 0}");
        return;
    }

    size_t numSamples = audioData.length / sizeof(float);
    const float *samples = (const float *)audioData.bytes;

    bool isSpeech = false;
    float probability = 0.0f;

    ra_result_code result = ra_vad_process(
        _backend,
        samples,
        numSamples,
        sampleRate,
        &isSpeech,
        &probability
    );

    if (result != RA_SUCCESS) {
        resolve(@"{\"isSpeech\": false, \"probability\": 0}");
        return;
    }

    NSString *resultJson = [NSString stringWithFormat:@"{\"isSpeech\": %@, \"probability\": %f}",
                           isSpeech ? @"true" : @"false", probability];
    resolve(resultJson);
}

RCT_EXPORT_METHOD(unloadVADModel:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_vad_unload_model(_backend) == RA_SUCCESS));
}

RCT_EXPORT_METHOD(detectVADSegments:(NSString *)audioBase64
                  sampleRate:(int)sampleRate
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@"[]");
        return;
    }

    NSData *audioData = [[NSData alloc] initWithBase64EncodedString:audioBase64 options:0];
    if (!audioData) {
        resolve(@"[]");
        return;
    }

    size_t numSamples = audioData.length / sizeof(float);
    const float *samples = (const float *)audioData.bytes;

    char *resultJson = nullptr;
    ra_result_code result = ra_vad_detect_segments(
        _backend,
        samples,
        numSamples,
        sampleRate,
        &resultJson
    );

    if (result != RA_SUCCESS || !resultJson) {
        resolve(@"[]");
        return;
    }

    NSString *resultStr = [NSString stringWithUTF8String:resultJson];
    ra_free_string(resultJson);
    resolve(resultStr);
}

RCT_EXPORT_METHOD(resetVAD) {
    if (_backend) {
        ra_vad_reset(_backend);
    }
}

// ============================================================================
// Utilities
// ============================================================================

RCT_EXPORT_METHOD(getLastError:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    const char *error = ra_get_last_error();
    resolve(error ? [NSString stringWithUTF8String:error] : @"");
}

RCT_EXPORT_METHOD(getVersion:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    const char *version = ra_get_version();
    resolve(version ? [NSString stringWithUTF8String:version] : @"unknown");
}

RCT_EXPORT_METHOD(extractArchive:(NSString *)archivePath
                  destDir:(NSString *)destDir
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    ra_result_code result = ra_extract_archive(
        [archivePath UTF8String],
        [destDir UTF8String]
    );
    resolve(@(result == RA_SUCCESS));
}

// ============================================================================
// Event Emitter Support
// ============================================================================

RCT_EXPORT_METHOD(addListener:(NSString *)eventName) {
    // Required for RN built-in event emitter
}

RCT_EXPORT_METHOD(removeListeners:(double)count) {
    // Required for RN built-in event emitter
}

// ============================================================================
// Model Registry Methods
// ============================================================================

RCT_EXPORT_METHOD(getAvailableModels:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSLog(@"[RunAnywhere] getAvailableModels called");

    NSDictionary *catalog = [self getModelCatalog];
    NSMutableArray *models = [NSMutableArray new];
    NSString *modelsDir = [self modelsDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSLog(@"[RunAnywhere] Models directory: %@", modelsDir);

    // List contents of models directory
    NSError *listError = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:modelsDir error:&listError];
    NSLog(@"[RunAnywhere] Models directory contents: %@", contents ?: @"ERROR");

    for (NSString *modelId in catalog) {
        NSMutableDictionary *model = [catalog[modelId] mutableCopy];

        // Check if model is downloaded
        NSString *modelPath = [modelsDir stringByAppendingPathComponent:modelId];
        BOOL isDirectory = NO;
        BOOL pathExists = [fm fileExistsAtPath:modelPath isDirectory:&isDirectory];
        BOOL isDownloaded = NO;
        NSString *actualModelPath = modelPath;

        if (pathExists && isDirectory) {
            NSArray *modelContents = [fm contentsOfDirectoryAtPath:modelPath error:nil];
            NSLog(@"[RunAnywhere] Model %@ contents: %@", modelId, modelContents);

            // Empty directory means incomplete download/extraction - treat as not downloaded
            if (modelContents.count == 0) {
                NSLog(@"[RunAnywhere] Model %@ directory is empty, treating as not downloaded", modelId);
                // Clean up empty directory
                [fm removeItemAtPath:modelPath error:nil];
                isDownloaded = NO;
            } else {
                NSString *format = model[@"format"];

                // For GGUF models (LLM), look for .gguf file
                if ([format isEqualToString:@"gguf"]) {
                    for (NSString *file in modelContents) {
                        if ([file hasSuffix:@".gguf"]) {
                            actualModelPath = [modelPath stringByAppendingPathComponent:file];
                            NSLog(@"[RunAnywhere] Found GGUF file: %@", actualModelPath);
                            isDownloaded = YES;
                            break;
                        }
                    }
                }
                // For ONNX models (VAD), look for .onnx file
                else if ([format isEqualToString:@"onnx"]) {
                    for (NSString *file in modelContents) {
                        if ([file hasSuffix:@".onnx"]) {
                            actualModelPath = [modelPath stringByAppendingPathComponent:file];
                            NSLog(@"[RunAnywhere] Found ONNX file: %@", actualModelPath);
                            isDownloaded = YES;
                            break;
                        }
                    }
                }
                // For Sherpa-ONNX models (STT/TTS), the directory structure is different
                // We return the directory and let the loader handle it
                else if ([format isEqualToString:@"sherpa-onnx"]) {
                    // Check if there's a subdirectory (extracted archive)
                    for (NSString *file in modelContents) {
                        BOOL isSubDir = NO;
                        NSString *subPath = [modelPath stringByAppendingPathComponent:file];
                        if ([fm fileExistsAtPath:subPath isDirectory:&isSubDir] && isSubDir) {
                            // Use the subdirectory as the model path for Sherpa-ONNX
                            actualModelPath = subPath;
                            NSLog(@"[RunAnywhere] Found Sherpa-ONNX model directory: %@", actualModelPath);
                            isDownloaded = YES;
                            break;
                        }
                    }
                    // If no subdirectory found, still consider downloaded if contents exist
                    // (might be a flat structure)
                    if (!isDownloaded && modelContents.count > 0) {
                        isDownloaded = YES;
                        NSLog(@"[RunAnywhere] Model %@ has contents but no subdirectory, using root path", modelId);
                    }
                }
                else {
                    // Unknown format with contents, assume downloaded
                    isDownloaded = YES;
                }
            }
        } else if (pathExists && !isDirectory) {
            // It's a file, not a directory (e.g., single .gguf file)
            isDownloaded = YES;
        }

        model[@"isDownloaded"] = @(isDownloaded);

        if (isDownloaded) {
            model[@"localPath"] = actualModelPath;
            NSLog(@"[RunAnywhere] Model %@ final path: %@", modelId, actualModelPath);
        }

        [models addObject:model];
    }

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:models options:0 error:&error];
    if (jsonData) {
        resolve([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
    } else {
        resolve(@"[]");
    }
}

RCT_EXPORT_METHOD(getModelInfo:(NSString *)modelId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSDictionary *catalog = [self getModelCatalog];
    NSDictionary *modelInfo = catalog[modelId];

    if (!modelInfo) {
        resolve(@"null");
        return;
    }

    NSMutableDictionary *model = [modelInfo mutableCopy];
    NSString *modelPath = [[self modelsDirectory] stringByAppendingPathComponent:modelId];
    BOOL isDownloaded = [[NSFileManager defaultManager] fileExistsAtPath:modelPath];
    model[@"isDownloaded"] = @(isDownloaded);
    if (isDownloaded) {
        model[@"localPath"] = modelPath;
    }

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:model options:0 error:&error];
    if (jsonData) {
        resolve([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
    } else {
        resolve(@"null");
    }
}

RCT_EXPORT_METHOD(isModelDownloaded:(NSString *)modelId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSString *modelPath = [[self modelsDirectory] stringByAppendingPathComponent:modelId];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:modelPath];
    resolve(@(exists));
}

RCT_EXPORT_METHOD(getModelPath:(NSString *)modelId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSString *modelPath = [[self modelsDirectory] stringByAppendingPathComponent:modelId];
    if ([[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
        resolve(modelPath);
    } else {
        resolve([NSNull null]);
    }
}

// ============================================================================
// Model Download Methods
// ============================================================================

RCT_EXPORT_METHOD(downloadModel:(NSString *)modelId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSDictionary *catalog = [self getModelCatalog];
    NSDictionary *modelInfo = catalog[modelId];

    if (!modelInfo) {
        reject(@"MODEL_NOT_FOUND", [NSString stringWithFormat:@"Model %@ not found in catalog", modelId], nil);
        return;
    }

    NSString *downloadUrl = modelInfo[@"downloadUrl"];
    if (!downloadUrl) {
        reject(@"NO_DOWNLOAD_URL", @"Model has no download URL", nil);
        return;
    }

    // Check if already downloading
    if (_downloadTasks[modelId]) {
        resolve(modelId);  // Return same task ID
        return;
    }

    NSURL *url = [NSURL URLWithString:downloadUrl];
    NSString *modelsDir = [self modelsDirectory];
    NSString *modelDir = [modelsDir stringByAppendingPathComponent:modelId];

    // Create model directory
    [[NSFileManager defaultManager] createDirectoryAtPath:modelDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Determine file extension from URL
    NSString *fileName = [url lastPathComponent];
    NSString *downloadPath = [modelsDir stringByAppendingPathComponent:fileName];

    __weak RunAnywhere *weakSelf = self;
    NSURLSessionDownloadTask *task = [_downloadSession downloadTaskWithURL:url
        completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            RunAnywhere *strongSelf = weakSelf;
            if (!strongSelf) return;

            [strongSelf->_downloadTasks removeObjectForKey:modelId];

            if (error) {
                [strongSelf sendEventWithName:@"onModelDownloadError"
                                        body:@{@"modelId": modelId, @"error": error.localizedDescription}];
                return;
            }

            NSFileManager *fm = [NSFileManager defaultManager];
            NSError *moveError = nil;

            // Move downloaded file
            NSURL *destURL = [NSURL fileURLWithPath:downloadPath];
            [fm removeItemAtURL:destURL error:nil];  // Remove if exists
            [fm moveItemAtURL:location toURL:destURL error:&moveError];

            if (moveError) {
                [strongSelf sendEventWithName:@"onModelDownloadError"
                                        body:@{@"modelId": modelId, @"error": moveError.localizedDescription}];
                return;
            }

            // Extract if it's an archive
            NSString *lowerPath = [downloadPath lowercaseString];
            BOOL isTarBz2 = [lowerPath hasSuffix:@".tar.bz2"] || [lowerPath hasSuffix:@".tbz2"];
            BOOL isTarGz = [lowerPath hasSuffix:@".tar.gz"] || [lowerPath hasSuffix:@".tgz"];
            BOOL isZip = [lowerPath hasSuffix:@".zip"];

            if (isTarBz2 || isTarGz || isZip) {
                NSLog(@"[RunAnywhere] Extracting archive: %@", downloadPath);

                // Clear the model directory before extraction to remove any stale contents
                [fm removeItemAtPath:modelDir error:nil];
                [fm createDirectoryAtPath:modelDir withIntermediateDirectories:YES attributes:nil error:nil];

                NSError *extractError = nil;
                BOOL extractSuccess = NO;

                if (isTarBz2) {
                    // Use our native tar.bz2 extraction (matching Swift SDK's ArchiveUtility)
                    extractSuccess = [strongSelf extractTarBz2:downloadPath toDirectory:modelDir error:&extractError];
                } else if (isTarGz) {
                    // TODO: Implement tar.gz extraction if needed
                    NSLog(@"[RunAnywhere] tar.gz extraction not yet implemented");
                    extractSuccess = NO;
                } else if (isZip) {
                    // TODO: Use ZIPFoundation equivalent if needed
                    NSLog(@"[RunAnywhere] zip extraction not yet implemented");
                    extractSuccess = NO;
                }

                if (extractSuccess) {
                    // Remove the archive after extraction
                    [fm removeItemAtPath:downloadPath error:nil];

                    // List extracted contents for debugging
                    NSArray *contents = [fm contentsOfDirectoryAtPath:modelDir error:nil];
                    NSLog(@"[RunAnywhere] Model %@ extracted contents: %@", modelId, contents);

                    [strongSelf sendEventWithName:@"onModelDownloadComplete"
                                            body:@{@"modelId": modelId, @"localPath": modelDir}];
                } else {
                    NSString *errorMsg = extractError ? extractError.localizedDescription : @"Failed to extract archive";
                    NSLog(@"[RunAnywhere] Extraction failed: %@", errorMsg);
                    [strongSelf sendEventWithName:@"onModelDownloadError"
                                            body:@{@"modelId": modelId, @"error": errorMsg}];
                }
            } else {
                // Not an archive, move directly to model dir
                NSString *finalPath = [modelDir stringByAppendingPathComponent:fileName];
                [fm moveItemAtPath:downloadPath toPath:finalPath error:nil];

                [strongSelf sendEventWithName:@"onModelDownloadComplete"
                                        body:@{@"modelId": modelId, @"localPath": modelDir}];
            }
        }];

    // Observe download progress
    [task addObserver:self forKeyPath:@"countOfBytesReceived" options:NSKeyValueObservingOptionNew context:(__bridge void *)modelId];
    [task addObserver:self forKeyPath:@"countOfBytesExpectedToReceive" options:NSKeyValueObservingOptionNew context:(__bridge void *)modelId];

    _downloadTasks[modelId] = task;
    [task resume];

    resolve(modelId);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if ([object isKindOfClass:[NSURLSessionDownloadTask class]]) {
        NSURLSessionDownloadTask *task = (NSURLSessionDownloadTask *)object;
        NSString *modelId = (__bridge NSString *)context;

        int64_t received = task.countOfBytesReceived;
        int64_t expected = task.countOfBytesExpectedToReceive;
        double progress = expected > 0 ? (double)received / (double)expected : 0;

        [self sendEventWithName:@"onModelDownloadProgress"
                           body:@{
                               @"modelId": modelId,
                               @"bytesDownloaded": @(received),
                               @"totalBytes": @(expected),
                               @"progress": @(progress)
                           }];
    }
}

RCT_EXPORT_METHOD(cancelDownload:(NSString *)modelId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSURLSessionDownloadTask *task = _downloadTasks[modelId];
    if (task) {
        @try {
            [task removeObserver:self forKeyPath:@"countOfBytesReceived"];
            [task removeObserver:self forKeyPath:@"countOfBytesExpectedToReceive"];
        } @catch (NSException *exception) {
            // Ignore if observer not registered
        }
        [task cancel];
        [_downloadTasks removeObjectForKey:modelId];
    }
    resolve(@YES);
}

RCT_EXPORT_METHOD(deleteModel:(NSString *)modelId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSString *modelPath = [[self modelsDirectory] stringByAppendingPathComponent:modelId];
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:modelPath error:&error];
    if (success || error.code == NSFileNoSuchFileError) {
        resolve(@YES);
    } else {
        reject(@"DELETE_FAILED", error.localizedDescription, error);
    }
}

RCT_EXPORT_METHOD(getDownloadedModels:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    NSString *modelsDir = [self modelsDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:modelsDir error:&error];

    if (error) {
        resolve(@"[]");
        return;
    }

    NSMutableArray *downloaded = [NSMutableArray new];
    NSDictionary *catalog = [self getModelCatalog];

    for (NSString *item in contents) {
        BOOL isDir = NO;
        NSString *fullPath = [modelsDir stringByAppendingPathComponent:item];
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
            NSDictionary *modelInfo = catalog[item];
            if (modelInfo) {
                NSMutableDictionary *model = [modelInfo mutableCopy];
                model[@"isDownloaded"] = @YES;
                model[@"localPath"] = fullPath;
                [downloaded addObject:model];
            } else {
                // Unknown model, just add basic info
                [downloaded addObject:@{
                    @"id": item,
                    @"name": item,
                    @"isDownloaded": @YES,
                    @"localPath": fullPath
                }];
            }
        }
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:downloaded options:0 error:nil];
    if (jsonData) {
        resolve([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
    } else {
        resolve(@"[]");
    }
}

@end

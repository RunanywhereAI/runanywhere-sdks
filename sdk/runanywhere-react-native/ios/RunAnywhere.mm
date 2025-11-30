#import "RunAnywhere.h"
#import <Foundation/Foundation.h>

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

@implementation RunAnywhere {
#ifdef RCT_NEW_ARCH_ENABLED
    std::shared_ptr<facebook::react::RunAnywhereModule> _nativeModule;
#endif
    ra_backend_handle _backend;
    NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *_downloadTasks;
    NSURLSession *_downloadSession;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _backend = nullptr;
        _downloadTasks = [NSMutableDictionary new];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 300;
        config.timeoutIntervalForResource = 600;
        _downloadSession = [NSURLSession sessionWithConfiguration:config
                                                         delegate:nil
                                                    delegateQueue:[NSOperationQueue mainQueue]];
    }
    return self;
}

- (void)dealloc {
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
        @"piper-en-us-lessac": @{
            @"id": @"piper-en-us-lessac",
            @"name": @"Piper US English (Lessac)",
            @"description": @"High quality US English TTS",
            @"category": @"tts",
            @"modality": @"tts",
            @"size": @(65000000),  // ~65MB
            @"downloadUrl": @"https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
            @"format": @"sherpa-onnx",
            @"modelType": @"piper"
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
    if (_backend) {
        ra_destroy(_backend);
        _backend = nullptr;
    }

    _backend = ra_create_backend([name UTF8String]);
    resolve(@(_backend != nullptr));
}

RCT_EXPORT_METHOD(initialize:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }

    ra_result_code result = ra_initialize(_backend, configJson ? [configJson UTF8String] : nullptr);
    resolve(@(result == RA_SUCCESS));
}

RCT_EXPORT_METHOD(destroy:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (_backend) {
        ra_destroy(_backend);
        _backend = nullptr;
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(isInitialized:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_is_initialized(_backend)));
}

RCT_EXPORT_METHOD(getBackendInfo:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@"{}");
        return;
    }

    char *info = ra_get_backend_info(_backend);
    if (info) {
        NSString *result = [NSString stringWithUTF8String:info];
        ra_free_string(info);
        resolve(result);
    } else {
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
    if (!_backend) {
        resolve(@NO);
        return;
    }

    ra_result_code result = ra_text_load_model(
        _backend,
        [path UTF8String],
        configJson ? [configJson UTF8String] : nullptr
    );
    resolve(@(result == RA_SUCCESS));
}

RCT_EXPORT_METHOD(isTextModelLoaded:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_text_is_model_loaded(_backend)));
}

RCT_EXPORT_METHOD(unloadTextModel:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_text_unload_model(_backend) == RA_SUCCESS));
}

RCT_EXPORT_METHOD(generate:(NSString *)prompt
                  systemPrompt:(NSString *)systemPrompt
                  maxTokens:(int)maxTokens
                  temperature:(double)temperature
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@"{\"error\": \"Backend not initialized\"}");
        return;
    }

    char *resultJson = nullptr;
    ra_result_code result = ra_text_generate(
        _backend,
        [prompt UTF8String],
        systemPrompt ? [systemPrompt UTF8String] : nullptr,
        maxTokens,
        (float)temperature,
        &resultJson
    );

    if (result != RA_SUCCESS || !resultJson) {
        const char *error = ra_get_last_error();
        NSString *errorMsg = error ? [NSString stringWithUTF8String:error] : @"Unknown error";
        resolve([NSString stringWithFormat:@"{\"error\": \"%@\"}", errorMsg]);
        return;
    }

    NSString *resultStr = [NSString stringWithUTF8String:resultJson];
    ra_free_string(resultJson);
    resolve(resultStr);
}

RCT_EXPORT_METHOD(generateStream:(NSString *)prompt
                  systemPrompt:(NSString *)systemPrompt
                  maxTokens:(int)maxTokens
                  temperature:(double)temperature) {
    if (!_backend) {
        [self sendEventWithName:@"onGenerationError"
                           body:@{@"error": @"Backend not initialized"}];
        return;
    }

    // For now, use non-streaming and send complete result
    // TODO: Implement actual streaming with callback
    char *resultJson = nullptr;
    ra_result_code result = ra_text_generate(
        _backend,
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
    if (!_backend) {
        resolve(@NO);
        return;
    }
    resolve(@(ra_supports_capability(_backend, (ra_capability_type)capability)));
}

RCT_EXPORT_METHOD(getCapabilities:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@[]);
        return;
    }

    ra_capability_type caps[10];
    int count = ra_get_capabilities(_backend, caps, 10);

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [result addObject:@(caps[i])];
    }
    resolve(result);
}

RCT_EXPORT_METHOD(getDeviceType:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@99); // RA_DEVICE_UNKNOWN
        return;
    }
    resolve(@(ra_get_device(_backend)));
}

RCT_EXPORT_METHOD(getMemoryUsage:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@0);
        return;
    }
    resolve(@(ra_get_memory_usage(_backend)));
}

// ============================================================================
// STT Methods
// ============================================================================

RCT_EXPORT_METHOD(loadSTTModel:(NSString *)path
                  modelType:(NSString *)modelType
                  configJson:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }

    ra_result_code result = ra_stt_load_model(
        _backend,
        [path UTF8String],
        [modelType UTF8String],
        configJson ? [configJson UTF8String] : nullptr
    );
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

// ============================================================================
// TTS Methods
// ============================================================================

RCT_EXPORT_METHOD(loadTTSModel:(NSString *)path
                  modelType:(NSString *)modelType
                  configJson:(NSString *)configJson
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    if (!_backend) {
        resolve(@NO);
        return;
    }

    ra_result_code result = ra_tts_load_model(
        _backend,
        [path UTF8String],
        [modelType UTF8String],
        configJson ? [configJson UTF8String] : nullptr
    );
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
    if (!_backend) {
        resolve(@NO);
        return;
    }

    ra_result_code result = ra_vad_load_model(
        _backend,
        [path UTF8String],
        configJson ? [configJson UTF8String] : nullptr
    );
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
    NSDictionary *catalog = [self getModelCatalog];
    NSMutableArray *models = [NSMutableArray new];

    for (NSString *modelId in catalog) {
        NSMutableDictionary *model = [catalog[modelId] mutableCopy];

        // Check if model is downloaded
        NSString *modelPath = [[self modelsDirectory] stringByAppendingPathComponent:modelId];
        BOOL isDownloaded = [[NSFileManager defaultManager] fileExistsAtPath:modelPath];
        model[@"isDownloaded"] = @(isDownloaded);
        if (isDownloaded) {
            model[@"localPath"] = modelPath;
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
            NSString *extension = [fileName pathExtension];
            if ([extension isEqualToString:@"bz2"] || [extension isEqualToString:@"gz"] ||
                [extension isEqualToString:@"zip"] || [extension isEqualToString:@"tar"]) {

                ra_result_code extractResult = ra_extract_archive([downloadPath UTF8String], [modelDir UTF8String]);

                if (extractResult == RA_SUCCESS) {
                    // Remove the archive after extraction
                    [fm removeItemAtPath:downloadPath error:nil];

                    [strongSelf sendEventWithName:@"onModelDownloadComplete"
                                            body:@{@"modelId": modelId, @"localPath": modelDir}];
                } else {
                    [strongSelf sendEventWithName:@"onModelDownloadError"
                                            body:@{@"modelId": modelId, @"error": @"Failed to extract archive"}];
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

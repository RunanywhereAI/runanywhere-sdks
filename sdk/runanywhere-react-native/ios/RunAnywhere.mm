#import "RunAnywhere.h"

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
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _backend = nullptr;
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
        @"onModelLoadProgress"
    ];
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

@end

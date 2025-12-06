//
// RunAnywhere.mm
// RunAnywhere React Native SDK - Objective-C++ Implementation
//
// This file provides the ObjC wrapper and TurboModule provider for the C++ TurboModule.
// All method implementations are in cpp/RunAnywhereModule.cpp.
//

#import "RunAnywhere.h"
#import <React/RCTLog.h>

#ifdef RCT_NEW_ARCH_ENABLED

// Import the C++ TurboModule class and React Native headers
#import "RunAnywhereModule.h"
#import <ReactCommon/RCTTurboModule.h>

using namespace facebook::react;

// Forward declare the C++ spec (no Objective-C protocol conformance needed)
@interface RunAnywhere ()
@end

@implementation RunAnywhere {
    std::shared_ptr<RunAnywhereModule> _module;
}

// Provide the module name for React Native's TurboModule system
+ (NSString *)moduleName {
    return @"RunAnywhere";
}

- (instancetype)init {
    NSLog(@"[RunAnywhere.mm] *** init called ***");
    if (self = [super init]) {
        NSLog(@"[RunAnywhere.mm] *** Initialized successfully ***");
    }
    return self;
}

// ============================================================================
// TurboModule Provider (NEW ARCHITECTURE)
// ============================================================================

/**
 * Returns the C++ TurboModule instance.
 * This is called by React Native's TurboModule system to get our C++ module.
 */
- (std::shared_ptr<TurboModule>)getTurboModule:
    (const ObjCTurboModule::InitParams &)params {
    NSLog(@"[RunAnywhere.mm] *** getTurboModule called - creating C++ RunAnywhereModule ***");
    if (!_module) {
        _module = std::make_shared<RunAnywhereModule>(params.jsInvoker);
        NSLog(@"[RunAnywhere.mm] *** Created C++ module: %p ***", _module.get());
    }
    return _module;
}

// ============================================================================
// RCTEventEmitter Overrides
// ============================================================================

- (NSArray<NSString *> *)supportedEvents {
    return @[
        @"onGenerationToken",
        @"onGenerationComplete",
        @"onTTSAudioChunk",
        @"onTTSComplete",
        @"onTranscriptionUpdate",
        @"onVADResult",
        @"onError"
    ];
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

@end

#else // !RCT_NEW_ARCH_ENABLED

// Old architecture fallback - not implemented
@implementation RunAnywhere

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
    return @[];
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

@end

#endif // RCT_NEW_ARCH_ENABLED

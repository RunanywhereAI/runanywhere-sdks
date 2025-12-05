//
// RunAnywhere.mm
// iOS Adapter for RunAnywhere C++ TurboModule
//
// This is a thin adapter that instantiates the C++ TurboModule.
// All business logic is in cpp/RunAnywhereModule.cpp.
//

#import "RunAnywhere.h"
#import <Foundation/Foundation.h>
#import <React/RCTBridge+Private.h>
#import <jsi/jsi.h>
#import "../cpp/RunAnywhereModule.h"

using namespace facebook::react;

@implementation RunAnywhere {
    std::shared_ptr<facebook::react::RunAnywhereModule> _nativeModule;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"[RunAnywhere] Initialized with New Architecture (C++ TurboModule)");
    }
    return self;
}

// TurboModule protocol - return C++ module
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {

    if (!_nativeModule) {
        NSLog(@"[RunAnywhere] Creating C++ TurboModule instance");
        _nativeModule = std::make_shared<facebook::react::RunAnywhereModule>(params.jsInvoker);
        NSLog(@"[RunAnywhere] C++ TurboModule created successfully");
    }

    return _nativeModule;
}

// Supported events for event emitter
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
        @"onTTSError"
    ];
}

@end

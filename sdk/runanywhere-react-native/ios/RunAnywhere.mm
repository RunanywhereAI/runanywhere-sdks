//
// RunAnywhere.mm
// Pure C++ TurboModule - iOS Adapter
//
// Minimal iOS adapter that connects the C++ TurboModule to React Native.
// All business logic is in cpp/RunAnywhereModule.cpp.
//
// REQUIRES: React Native New Architecture (TurboModules)
//

#import <React/RCTBridgeModule.h>
#import <ReactCommon/RCTTurboModule.h>
#import "../cpp/RunAnywhereModule.h"

#ifdef RCT_NEW_ARCH_ENABLED
#import <RunAnywhereSpec/RunAnywhereSpec.h>
#endif

using namespace facebook::react;

#ifdef RCT_NEW_ARCH_ENABLED
@interface RunAnywhere : NSObject <NativeRunAnywhereSpec>
#else
@interface RunAnywhere : NSObject <RCTBridgeModule, RCTTurboModule>
#endif
@end

@implementation RunAnywhere {
    std::shared_ptr<RunAnywhereModule> _nativeModule;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

// Return the C++ TurboModule instance
- (std::shared_ptr<TurboModule>)getTurboModule:(const ObjCTurboModule::InitParams &)params {
    if (!_nativeModule) {
        _nativeModule = std::make_shared<RunAnywhereModule>(params.jsInvoker);
    }
    return _nativeModule;
}

@end

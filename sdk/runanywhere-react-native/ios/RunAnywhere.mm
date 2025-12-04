//
// RunAnywhere_MINIMAL.mm
// Pure C++ TurboModule - Minimal iOS Adapter
//
// This is the MINIMAL iOS adapter for the Pure C++ TurboModule approach.
// Replace RunAnywhere.mm with this file to remove all business logic from Obj-C++.
//

#import <React/RCTBridgeModule.h>
#import <ReactCommon/RCTTurboModule.h>
#import "../cpp/RunAnywhereModule.h"

using namespace facebook::react;

@interface RunAnywhere : NSObject <RCTBridgeModule, RCTTurboModule>
@end

@implementation RunAnywhere {
    std::shared_ptr<RunAnywhereModule> _nativeModule;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

// TurboModule protocol - return C++ module
- (std::shared_ptr<TurboModule>)getTurboModule:
    (const ObjCTurboModule::InitParams &)params {

    if (!_nativeModule) {
        _nativeModule = std::make_shared<RunAnywhereModule>(params.jsInvoker);
    }

    return _nativeModule;
}

@end

// ============================================================================
// THAT'S IT! All 60 methods are implemented in C++ TurboModule.
// NO RCT_EXPORT_METHOD needed here!
// ============================================================================

#import <Foundation/Foundation.h>
#import <React/RCTEventEmitter.h>

#ifdef RCT_NEW_ARCH_ENABLED

#import <ReactCommon/RCTTurboModule.h>

// New architecture - provides C++ TurboModule via getTurboModule:
// The C++ class RunAnywhereModule (cpp/RunAnywhereModule.h) implements the TurboModule
@interface RunAnywhere : RCTEventEmitter <RCTTurboModule>
@end

#else

// Old architecture fallback
@interface RunAnywhere : RCTEventEmitter <RCTBridgeModule>
@end

#endif

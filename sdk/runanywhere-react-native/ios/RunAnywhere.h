#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <ReactCommon/RCTTurboModule.h>
#endif

/**
 * RunAnywhere React Native Module
 *
 * This is the Objective-C++ bridge that connects React Native to the
 * C++ TurboModule implementation (RunAnywhereModule.cpp).
 *
 * For the New Architecture (TurboModules), it uses direct C++ invocation.
 * For the Old Architecture (Bridge), it falls back to the bridge module.
 */

#ifdef RCT_NEW_ARCH_ENABLED
@interface RunAnywhere : RCTEventEmitter <RCTBridgeModule, RCTTurboModule>
#else
@interface RunAnywhere : RCTEventEmitter <RCTBridgeModule>
#endif

@end

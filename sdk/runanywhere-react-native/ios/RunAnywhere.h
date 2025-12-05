#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <ReactCommon/RCTTurboModule.h>

/**
 * RunAnywhere React Native Module
 *
 * This is the Objective-C++ bridge that connects React Native to the
 * C++ TurboModule implementation (RunAnywhereModule.cpp).
 *
 * Pure C++ TurboModule architecture - New Architecture only (RN 0.74+)
 */

@interface RunAnywhere : RCTEventEmitter <RCTBridgeModule, RCTTurboModule>

@end

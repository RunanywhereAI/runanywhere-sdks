//
// RunAnywhereTurboModuleProvider.mm
// RunAnywhere React Native SDK - C++ TurboModule Provider for iOS
//
// This file registers the C++ TurboModule with React Native's module system.
//

#import <Foundation/Foundation.h>

#ifdef RCT_NEW_ARCH_ENABLED

#import <ReactCommon/RCTTurboModuleManager.h>
#import <ReactCommon/CxxTurboModuleUtils.h>
#import "RunAnywhereModule.h"
#import "RunAnywhereSpecJSI.h"

using namespace facebook::react;

/**
 * C++ TurboModule provider for RunAnywhere
 * This function is called by React Native when requesting the "RunAnywhere" module
 */
std::shared_ptr<TurboModule> RunAnywhereTurboModuleProvider(
    const std::string &moduleName,
    const std::shared_ptr<CallInvoker> &jsInvoker) {

    NSLog(@"[RunAnywhereTurboModuleProvider] Called for module: %s", moduleName.c_str());

    if (moduleName == "RunAnywhere") {
        NSLog(@"[RunAnywhereTurboModuleProvider] Creating RunAnywhereModule");
        return std::make_shared<RunAnywhereModule>(jsInvoker);
    }

    return nullptr;
}

/**
 * Register the C++ TurboModule provider
 * This uses Objective-C's +load method to register before the app starts
 */
@interface RunAnywhereTurboModuleRegistry : NSObject
@end

@implementation RunAnywhereTurboModuleRegistry

+ (void)load {
    NSLog(@"[RunAnywhereTurboModuleRegistry] Registering C++ TurboModule to global map");

    // Register the C++ TurboModule to the global module map
    // This is the ONLY reliable way to make pure C++ TurboModules discoverable
    facebook::react::registerCxxModuleToGlobalModuleMap(
        "RunAnywhere",
        [](std::shared_ptr<facebook::react::CallInvoker> jsInvoker) {
            NSLog(@"[RunAnywhereTurboModuleRegistry] Creating RunAnywhereModule instance");
            return std::make_shared<facebook::react::RunAnywhereModule>(jsInvoker);
        });
    
    NSLog(@"[RunAnywhereTurboModuleRegistry] C++ TurboModule registered successfully");
}

@end

#endif // RCT_NEW_ARCH_ENABLED

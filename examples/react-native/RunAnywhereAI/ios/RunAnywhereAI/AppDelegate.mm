#import "AppDelegate.h"

#import <React/RCTBundleURLProvider.h>

// Import the RunAnywhere TurboModule C++ header
#import "RunAnywhereModule.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.moduleName = @"RunAnywhereAI";
  // You can add your custom initial props in the dictionary below.
  // They will be passed down to the ViewController used by React Native.
  self.initialProps = @{};

  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
  // Always check for bundled JS file first (even in Debug mode)
  // This allows testing without Metro bundler running
  NSURL *jsBundleURL = [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];

  if (jsBundleURL != nil) {
    NSLog(@"[AppDelegate] Loading from bundled main.jsbundle");
    return jsBundleURL;
  }

#if DEBUG
  NSLog(@"[AppDelegate] No bundle found, connecting to Metro bundler");
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  NSLog(@"[AppDelegate] ERROR: No bundle found in Release mode!");
  return nil;
#endif
}

// TurboModule provider registration happens automatically via RCT_NEW_ARCH_ENABLED
// The RunAnywhereModule is registered through the codegen system

@end

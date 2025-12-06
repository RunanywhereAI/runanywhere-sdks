//
//  RunAnywhereBridge.h
//  runanywhere
//
//  Re-exports C symbols from RunAnywhereCore.xcframework to make them accessible via Dart FFI.
//  This is required because static libraries in XCFrameworks don't automatically expose symbols
//  to DynamicLibrary.process() or DynamicLibrary.executable().
//

#import <Foundation/Foundation.h>

// Import the RunAnywhereCore umbrella header
#import <RunAnywhereCore/ra_core.h>

// Re-export all RunAnywhere core functions so Dart FFI can find them
// Note: We don't need to redefine them, just ensure they're in the plugin's symbol table

__attribute__((visibility("default")))
@interface RunAnywhereBridge : NSObject
+ (void)forceSymbolLoading;
@end

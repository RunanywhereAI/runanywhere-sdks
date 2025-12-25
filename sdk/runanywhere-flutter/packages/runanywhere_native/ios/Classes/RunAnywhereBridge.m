//
//  RunAnywhereBridge.m
//  runanywhere_native
//
//  Forces symbols from RunAnywhereCore.xcframework to be loaded and accessible.
//

#import "RunAnywhereBridge.h"

@implementation RunAnywhereBridge

+ (void)forceSymbolLoading {
    // Call a function from RunAnywhereCore to force linking
    // This ensures all symbols are loaded into the process

    // Call ra_get_available_backends to force the library to be linked
    size_t count = 0;
    const char** backends = ra_get_available_backends(&count);

    // Don't actually use the result, just force the symbol to be present
    (void)backends;
    (void)count;
}

@end

// Additional: Create C wrapper functions that Dart can call
// These act as a bridge from Dart FFI -> Objective-C -> C library

#ifdef __cplusplus
extern "C" {
#endif

// Export all ra_ functions with the same signatures
// This makes them available to Dart FFI via DynamicLibrary.process()

__attribute__((visibility("default")))
const char** ra_get_available_backends_wrapper(size_t* count) {
    return ra_get_available_backends(count);
}

#ifdef __cplusplus
}
#endif

/**
 * ArchiveUtilityBridge.m
 *
 * C bridge to call Swift ArchiveUtility from C++.
 * This bridge is necessary because C++ cannot directly call Swift code.
 */

#import <Foundation/Foundation.h>
#import "RNSDKLoggerBridge.h"

static NSString * const kLogCategory = @"ArchiveBridge";

// Import the generated Swift header from the pod
#if __has_include(<RunAnywhereCore/RunAnywhereCore-Swift.h>)
#import <RunAnywhereCore/RunAnywhereCore-Swift.h>
#elif __has_include("RunAnywhereCore-Swift.h")
#import "RunAnywhereCore-Swift.h"
#else
// Forward declare the Swift class if header not found
@interface ArchiveUtility : NSObject
+ (BOOL)extractWithArchivePath:(NSString * _Nonnull)archivePath to:(NSString * _Nonnull)destinationPath;
@end
#endif

/**
 * Extract an archive to a destination directory
 * Called from C++ HybridRunAnywhereCore::extractArchive
 */
bool ArchiveUtility_extract(const char* archivePath, const char* destinationPath) {
    @autoreleasepool {
        if (archivePath == NULL || destinationPath == NULL) {
            RN_LOG_ERROR(kLogCategory, @"Invalid null path");
            return false;
        }

        NSString* archivePathStr = [NSString stringWithUTF8String:archivePath];
        NSString* destinationPathStr = [NSString stringWithUTF8String:destinationPath];

        if (archivePathStr == nil || destinationPathStr == nil) {
            RN_LOG_ERROR(kLogCategory, @"Failed to create NSString from path");
            return false;
        }

        @try {
            BOOL result = [ArchiveUtility extractWithArchivePath:archivePathStr to:destinationPathStr];
            return result;
        } @catch (NSException *exception) {
            RN_LOG_ERROR(kLogCategory, @"Exception: %@", exception);
            return false;
        }
    }
}

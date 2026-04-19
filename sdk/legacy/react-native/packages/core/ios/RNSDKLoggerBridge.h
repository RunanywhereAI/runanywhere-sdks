/**
 * RNSDKLoggerBridge.h
 *
 * Objective-C bridge header for SDKLogger.
 * Allows C and Objective-C code to use the Swift SDKLogger.
 */

#ifndef RNSDKLoggerBridge_h
#define RNSDKLoggerBridge_h

#import <Foundation/Foundation.h>

/**
 * Log level enum matching Swift RNLogLevel
 */
typedef NS_ENUM(NSInteger, RNLogLevelObjC) {
    RNLogLevelObjCDebug = 0,
    RNLogLevelObjCInfo = 1,
    RNLogLevelObjCWarning = 2,
    RNLogLevelObjCError = 3,
    RNLogLevelObjCFault = 4
};

/**
 * Log a message with the specified category and level.
 * @param category Logger category (e.g., "Archive", "AudioDecoder")
 * @param level Log level
 * @param message Log message
 */
void RNSDKLoggerLog(NSString * _Nonnull category, RNLogLevelObjC level, NSString * _Nonnull message);

/**
 * Convenience macros for logging from Objective-C
 */
#define RN_LOG_DEBUG(category, ...) RNSDKLoggerLog(category, RNLogLevelObjCDebug, [NSString stringWithFormat:__VA_ARGS__])
#define RN_LOG_INFO(category, ...) RNSDKLoggerLog(category, RNLogLevelObjCInfo, [NSString stringWithFormat:__VA_ARGS__])
#define RN_LOG_WARNING(category, ...) RNSDKLoggerLog(category, RNLogLevelObjCWarning, [NSString stringWithFormat:__VA_ARGS__])
#define RN_LOG_ERROR(category, ...) RNSDKLoggerLog(category, RNLogLevelObjCError, [NSString stringWithFormat:__VA_ARGS__])
#define RN_LOG_FAULT(category, ...) RNSDKLoggerLog(category, RNLogLevelObjCFault, [NSString stringWithFormat:__VA_ARGS__])

#endif /* RNSDKLoggerBridge_h */

/**
 * RNSDKLoggerBridge.m
 *
 * Implementation of the Objective-C bridge for SDKLogger.
 * Routes log messages to the Swift SDKLogger.
 */

#import "RNSDKLoggerBridge.h"

// Import the generated Swift header from the pod
#if __has_include(<RunAnywhereCore/RunAnywhereCore-Swift.h>)
#import <RunAnywhereCore/RunAnywhereCore-Swift.h>
#elif __has_include("RunAnywhereCore-Swift.h")
#import "RunAnywhereCore-Swift.h"
#else
// Fallback: Forward declare the Swift class if header not found
@interface SDKLogger : NSObject
- (instancetype _Nonnull)initWithCategory:(NSString * _Nonnull)category;
- (void)debug:(NSString * _Nonnull)message metadata:(NSDictionary<NSString *, id> * _Nullable)metadata;
- (void)info:(NSString * _Nonnull)message metadata:(NSDictionary<NSString *, id> * _Nullable)metadata;
- (void)warning:(NSString * _Nonnull)message metadata:(NSDictionary<NSString *, id> * _Nullable)metadata;
- (void)error:(NSString * _Nonnull)message metadata:(NSDictionary<NSString *, id> * _Nullable)metadata;
- (void)fault:(NSString * _Nonnull)message metadata:(NSDictionary<NSString *, id> * _Nullable)metadata;
@end
#endif

// Cache loggers for common categories
static NSMutableDictionary<NSString *, SDKLogger *> *loggerCache = nil;

static SDKLogger *getLogger(NSString *category) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loggerCache = [NSMutableDictionary new];
    });

    @synchronized (loggerCache) {
        SDKLogger *logger = loggerCache[category];
        if (!logger) {
            logger = [[SDKLogger alloc] initWithCategory:category];
            loggerCache[category] = logger;
        }
        return logger;
    }
}

void RNSDKLoggerLog(NSString * _Nonnull category, RNLogLevelObjC level, NSString * _Nonnull message) {
    SDKLogger *logger = getLogger(category);

    switch (level) {
        case RNLogLevelObjCDebug:
            [logger debug:message metadata:nil];
            break;
        case RNLogLevelObjCInfo:
            [logger info:message metadata:nil];
            break;
        case RNLogLevelObjCWarning:
            [logger warning:message metadata:nil];
            break;
        case RNLogLevelObjCError:
            [logger error:message metadata:nil];
            break;
        case RNLogLevelObjCFault:
            [logger fault:message metadata:nil];
            break;
    }
}

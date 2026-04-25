/**
 * PlatformAdapterBridge.m
 *
 * C bridge to call Swift PlatformAdapter/KeychainManager from C++.
 * This bridge is necessary because C++ cannot directly call Swift code.
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PlatformDownloadBridge.h"

// Import the generated Swift header from the pod
#if __has_include(<RunAnywhereCore/RunAnywhereCore-Swift.h>)
#import <RunAnywhereCore/RunAnywhereCore-Swift.h>
#elif __has_include("RunAnywhereCore-Swift.h")
#import "RunAnywhereCore-Swift.h"
#else
// Forward declare the Swift classes if header not found
@interface KeychainManager : NSObject
+ (KeychainManager * _Nonnull)shared;
- (BOOL)set:(NSString * _Nonnull)value forKey:(NSString * _Nonnull)key;
- (NSString * _Nullable)getForKey:(NSString * _Nonnull)key;
- (BOOL)deleteForKey:(NSString * _Nonnull)key;
- (BOOL)existsForKey:(NSString * _Nonnull)key;
@end

@interface PlatformAdapter : NSObject
+ (PlatformAdapter * _Nonnull)shared;
- (NSString * _Nonnull)getPersistentDeviceUUID;
@end
#endif

// =============================================================================
// HTTP Download (Platform Adapter Fallback)
//
// Public RN model downloads bypass this Objective-C path and call
// HybridRunAnywhereCore::downloadModel -> rac_http_download_execute. This
// fallback remains registered on the RACommons platform adapter for
// platform-adapter-only consumers that request an async download before going
// through the Nitro public API.
// =============================================================================

static const int RAC_SUCCESS = 0;
static const int RAC_ERROR_INVALID_PARAMETER = -106;
static const int RAC_ERROR_DOWNLOAD_FAILED = -153;
static const int RAC_ERROR_CANCELLED = -380;

@interface RunAnywhereHttpDownloadTaskInfo : NSObject
@property(nonatomic, copy) NSString* taskId;
@property(nonatomic, copy) NSString* destinationPath;
@property(nonatomic, assign) BOOL cancelled;
@end

@implementation RunAnywhereHttpDownloadTaskInfo
@end

@interface RunAnywhereHttpDownloadManager : NSObject <NSURLSessionDownloadDelegate>
@property(nonatomic, strong) NSURLSession* session;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, RunAnywhereHttpDownloadTaskInfo*>* taskInfoByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSURLSessionDownloadTask*>* taskById;
@property(nonatomic, strong) NSMutableDictionary<NSString*, NSString*>* completedPathById;
+ (instancetype)shared;
- (int)startDownload:(NSString*)url destination:(NSString*)destination taskId:(NSString*)taskId;
- (BOOL)cancelDownload:(NSString*)taskId;
@end

@implementation RunAnywhereHttpDownloadManager

+ (instancetype)shared {
    static RunAnywhereHttpDownloadManager* instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RunAnywhereHttpDownloadManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSOperationQueue* queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 4;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
        _taskInfoByIdentifier = [NSMutableDictionary dictionary];
        _taskById = [NSMutableDictionary dictionary];
        _completedPathById = [NSMutableDictionary dictionary];
    }
    return self;
}

- (int)startDownload:(NSString*)url destination:(NSString*)destination taskId:(NSString*)taskId {
    if (url.length == 0 || destination.length == 0 || taskId.length == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    NSURL* downloadURL = [NSURL URLWithString:url];
    if (!downloadURL) {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    NSURLSessionDownloadTask* task = [self.session downloadTaskWithURL:downloadURL];
    RunAnywhereHttpDownloadTaskInfo* info = [[RunAnywhereHttpDownloadTaskInfo alloc] init];
    info.taskId = taskId;
    info.destinationPath = destination;
    info.cancelled = NO;

    @synchronized (self) {
        self.taskInfoByIdentifier[@(task.taskIdentifier)] = info;
        self.taskById[taskId] = task;
    }

    [task resume];
    return RAC_SUCCESS;
}

- (BOOL)cancelDownload:(NSString*)taskId {
    if (taskId.length == 0) {
        return NO;
    }

    NSURLSessionDownloadTask* task = nil;
    @synchronized (self) {
        task = self.taskById[taskId];
        if (task) {
            RunAnywhereHttpDownloadTaskInfo* info = self.taskInfoByIdentifier[@(task.taskIdentifier)];
            if (info) {
                info.cancelled = YES;
            }
        }
    }

    if (!task) {
        return NO;
    }

    [task cancel];
    return YES;
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession*)session
      downloadTask:(NSURLSessionDownloadTask*)downloadTask
 didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    (void)session;
    RunAnywhereHttpDownloadTaskInfo* info = nil;
    @synchronized (self) {
        info = self.taskInfoByIdentifier[@(downloadTask.taskIdentifier)];
    }
    if (!info) {
        return;
    }
    RunAnywhereHttpDownloadReportProgress(
        info.taskId.UTF8String,
        totalBytesWritten,
        totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
    );
}

- (void)URLSession:(NSURLSession*)session
      downloadTask:(NSURLSessionDownloadTask*)downloadTask
didFinishDownloadingToURL:(NSURL*)location {
    (void)session;
    RunAnywhereHttpDownloadTaskInfo* info = nil;
    @synchronized (self) {
        info = self.taskInfoByIdentifier[@(downloadTask.taskIdentifier)];
    }
    if (!info) {
        return;
    }

    NSString* destination = info.destinationPath;
    NSString* destinationDir = [destination stringByDeletingLastPathComponent];
    NSError* error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:destinationDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        return;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:destination]) {
        [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
    }

    if ([[NSFileManager defaultManager] moveItemAtURL:location
                                                toURL:[NSURL fileURLWithPath:destination]
                                                error:&error]) {
        @synchronized (self) {
            self.completedPathById[info.taskId] = destination;
        }
    }
}

- (void)URLSession:(NSURLSession*)session
              task:(NSURLSessionTask*)task
didCompleteWithError:(NSError*)error {
    (void)session;
    RunAnywhereHttpDownloadTaskInfo* info = nil;
    NSString* completedPath = nil;

    @synchronized (self) {
        info = self.taskInfoByIdentifier[@(task.taskIdentifier)];
        if (info) {
            [self.taskInfoByIdentifier removeObjectForKey:@(task.taskIdentifier)];
            [self.taskById removeObjectForKey:info.taskId];
            completedPath = self.completedPathById[info.taskId];
            if (completedPath) {
                [self.completedPathById removeObjectForKey:info.taskId];
            }
        }
    }

    if (!info) {
        return;
    }

    int result = RAC_SUCCESS;
    if (error) {
        if (info.cancelled || error.code == NSURLErrorCancelled) {
            result = RAC_ERROR_CANCELLED;
        } else {
            result = RAC_ERROR_DOWNLOAD_FAILED;
        }
    } else if (!completedPath) {
        result = RAC_ERROR_DOWNLOAD_FAILED;
    }

    const char* pathCString = completedPath ? completedPath.UTF8String : NULL;
    RunAnywhereHttpDownloadReportComplete(info.taskId.UTF8String, result, pathCString);
}

@end

// ============================================================================
// Secure Storage (Keychain)
// ============================================================================

/**
 * Set a value in the Keychain
 * @param key The key to store under
 * @param value The value to store
 * @return true if successful
 */
bool PlatformAdapter_secureSet(const char* key, const char* value) {
    @autoreleasepool {
        if (key == NULL || value == NULL) {
            NSLog(@"[PlatformAdapterBridge] secureSet: Invalid null key or value");
            return false;
        }

        NSString* keyStr = [NSString stringWithUTF8String:key];
        NSString* valueStr = [NSString stringWithUTF8String:value];

        if (keyStr == nil || valueStr == nil) {
            NSLog(@"[PlatformAdapterBridge] secureSet: Failed to create NSString");
            return false;
        }

        @try {
            BOOL result = [[KeychainManager shared] set:valueStr forKey:keyStr];
            NSLog(@"[PlatformAdapterBridge] secureSet key=%@ result=%d", keyStr, result);
            return result;
        } @catch (NSException *exception) {
            NSLog(@"[PlatformAdapterBridge] secureSet exception: %@", exception);
            return false;
        }
    }
}

/**
 * Get a value from the Keychain
 * @param key The key to retrieve
 * @param outValue Pointer to store the result (must be freed by caller)
 * @return true if found
 */
bool PlatformAdapter_secureGet(const char* key, char** outValue) {
    @autoreleasepool {
        if (key == NULL || outValue == NULL) {
            NSLog(@"[PlatformAdapterBridge] secureGet: Invalid null key or outValue");
            return false;
        }

        *outValue = NULL;

        NSString* keyStr = [NSString stringWithUTF8String:key];
        if (keyStr == nil) {
            NSLog(@"[PlatformAdapterBridge] secureGet: Failed to create NSString for key");
            return false;
        }

        @try {
            NSString* value = [[KeychainManager shared] getForKey:keyStr];
            if (value == nil) {
                NSLog(@"[PlatformAdapterBridge] secureGet key=%@ not found", keyStr);
                return false;
            }

            const char* utf8Value = [value UTF8String];
            if (utf8Value == NULL) {
                return false;
            }

            *outValue = strdup(utf8Value);
            NSLog(@"[PlatformAdapterBridge] secureGet key=%@ found", keyStr);
            return *outValue != NULL;
        } @catch (NSException *exception) {
            NSLog(@"[PlatformAdapterBridge] secureGet exception: %@", exception);
            return false;
        }
    }
}

/**
 * Delete a value from the Keychain
 * @param key The key to delete
 * @return true if successful
 */
bool PlatformAdapter_secureDelete(const char* key) {
    @autoreleasepool {
        if (key == NULL) {
            NSLog(@"[PlatformAdapterBridge] secureDelete: Invalid null key");
            return false;
        }

        NSString* keyStr = [NSString stringWithUTF8String:key];
        if (keyStr == nil) {
            return false;
        }

        @try {
            BOOL result = [[KeychainManager shared] deleteForKey:keyStr];
            return result;
        } @catch (NSException *exception) {
            NSLog(@"[PlatformAdapterBridge] secureDelete exception: %@", exception);
            return false;
        }
    }
}

/**
 * Check if a key exists in the Keychain
 * @param key The key to check
 * @return true if exists
 */
bool PlatformAdapter_secureExists(const char* key) {
    @autoreleasepool {
        if (key == NULL) {
            return false;
        }

        NSString* keyStr = [NSString stringWithUTF8String:key];
        if (keyStr == nil) {
            return false;
        }

        @try {
            return [[KeychainManager shared] existsForKey:keyStr];
        } @catch (NSException *exception) {
            return false;
        }
    }
}

/**
 * Get persistent device UUID (from Keychain or generate new)
 * @param outValue Pointer to store the UUID (must be freed by caller)
 * @return true if successful
 */
bool PlatformAdapter_getPersistentDeviceUUID(char** outValue) {
    @autoreleasepool {
        if (outValue == NULL) {
            return false;
        }

        *outValue = NULL;

        @try {
            NSString* uuid = [[PlatformAdapter shared] getPersistentDeviceUUID];
            if (uuid == nil || uuid.length == 0) {
                NSLog(@"[PlatformAdapterBridge] getPersistentDeviceUUID: Failed to get UUID");
                return false;
            }

            const char* utf8Value = [uuid UTF8String];
            if (utf8Value == NULL) {
                return false;
            }

            *outValue = strdup(utf8Value);
            NSLog(@"[PlatformAdapterBridge] getPersistentDeviceUUID: %@", uuid);
            return *outValue != NULL;
        } @catch (NSException *exception) {
            NSLog(@"[PlatformAdapterBridge] getPersistentDeviceUUID exception: %@", exception);
            return false;
        }
    }
}

// ============================================================================
// Device Info (Synchronous)
// ============================================================================

#import <sys/utsname.h>
#import <mach/mach.h>

/**
 * Get the raw machine identifier (e.g., "iPhone17,1")
 */
static NSString* getMachineIdentifier(void) {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

/**
 * Get human-readable device model name
 */
static NSString* getDeviceModelName(NSString* identifier) {
    // iPhone models
    NSDictionary* models = @{
        // iPhone 16 series
        @"iPhone17,1": @"iPhone 16 Pro",
        @"iPhone17,2": @"iPhone 16 Pro Max",
        @"iPhone17,3": @"iPhone 16",
        @"iPhone17,4": @"iPhone 16 Plus",
        // iPhone 15 series
        @"iPhone16,1": @"iPhone 15 Pro",
        @"iPhone16,2": @"iPhone 15 Pro Max",
        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        // iPhone 14 series
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone14,7": @"iPhone 14",
        @"iPhone14,8": @"iPhone 14 Plus",
        // iPad models
        @"iPad14,1": @"iPad Pro 11-inch (4th generation)",
        @"iPad14,2": @"iPad Pro 12.9-inch (6th generation)",
        // Simulator
        @"x86_64": @"Simulator",
        @"arm64": @"Simulator",
    };
    
    NSString* name = models[identifier];
    return name ?: identifier;
}

/**
 * Get chip name for device model
 */
static NSString* getChipNameForModel(NSString* identifier) {
    NSDictionary* chips = @{
        // A18 Pro
        @"iPhone17,1": @"A18 Pro",
        @"iPhone17,2": @"A18 Pro",
        // A18
        @"iPhone17,3": @"A18",
        @"iPhone17,4": @"A18",
        // A17 Pro
        @"iPhone16,1": @"A17 Pro",
        @"iPhone16,2": @"A17 Pro",
        // A16 Bionic
        @"iPhone15,2": @"A16 Bionic",
        @"iPhone15,3": @"A16 Bionic",
        @"iPhone15,4": @"A16 Bionic",
        @"iPhone15,5": @"A16 Bionic",
        // A15 Bionic
        @"iPhone14,7": @"A15 Bionic",
        @"iPhone14,8": @"A15 Bionic",
        // M2
        @"iPad14,1": @"M2",
        @"iPad14,2": @"M2",
    };
    
    NSString* chip = chips[identifier];
    return chip ?: @"Apple Silicon";
}

bool PlatformAdapter_getDeviceModel(char** outValue) {
    @autoreleasepool {
        if (!outValue) return false;
        *outValue = NULL;
        
        @try {
            NSString* identifier = getMachineIdentifier();
            
            // Check for simulator
            #if TARGET_OS_SIMULATOR
            NSDictionary* env = [[NSProcessInfo processInfo] environment];
            NSString* simModelId = env[@"SIMULATOR_MODEL_IDENTIFIER"];
            if (simModelId) {
                identifier = simModelId;
            }
            #endif
            
            NSString* modelName = getDeviceModelName(identifier);
            *outValue = strdup([modelName UTF8String]);
            return *outValue != NULL;
        } @catch (NSException* exception) {
            return false;
        }
    }
}

bool PlatformAdapter_getOSVersion(char** outValue) {
    @autoreleasepool {
        if (!outValue) return false;
        *outValue = NULL;
        
        @try {
            NSString* version = [[UIDevice currentDevice] systemVersion];
            *outValue = strdup([version UTF8String]);
            return *outValue != NULL;
        } @catch (NSException* exception) {
            return false;
        }
    }
}

bool PlatformAdapter_getChipName(char** outValue) {
    @autoreleasepool {
        if (!outValue) return false;
        *outValue = NULL;
        
        @try {
            NSString* identifier = getMachineIdentifier();
            
            // Check for simulator
            #if TARGET_OS_SIMULATOR
            NSDictionary* env = [[NSProcessInfo processInfo] environment];
            NSString* simModelId = env[@"SIMULATOR_MODEL_IDENTIFIER"];
            if (simModelId) {
                identifier = simModelId;
            }
            #endif
            
            NSString* chipName = getChipNameForModel(identifier);
            *outValue = strdup([chipName UTF8String]);
            return *outValue != NULL;
        } @catch (NSException* exception) {
            return false;
        }
    }
}

uint64_t PlatformAdapter_getTotalMemory(void) {
    return [NSProcessInfo processInfo].physicalMemory;
}

uint64_t PlatformAdapter_getAvailableMemory(void) {
    vm_statistics64_data_t vmStats;
    mach_msg_type_number_t infoCount = HOST_VM_INFO64_COUNT;
    kern_return_t result = host_statistics64(mach_host_self(), HOST_VM_INFO64,
                                              (host_info64_t)&vmStats, &infoCount);
    if (result != KERN_SUCCESS) {
        return 0;
    }
    
    uint64_t pageSize = vm_page_size;
    uint64_t freeMemory = vmStats.free_count * pageSize;
    uint64_t inactiveMemory = vmStats.inactive_count * pageSize;
    
    return freeMemory + inactiveMemory;
}

int PlatformAdapter_getCoreCount(void) {
    return (int)[[NSProcessInfo processInfo] processorCount];
}

bool PlatformAdapter_getArchitecture(char** outValue) {
    @autoreleasepool {
        if (!outValue) return false;
        *outValue = NULL;
        
        @try {
            #if __arm64__
            *outValue = strdup("arm64");
            #elif __x86_64__
            *outValue = strdup("x86_64");
            #else
            *outValue = strdup("unknown");
            #endif
            return *outValue != NULL;
        } @catch (NSException* exception) {
            return false;
        }
    }
}

bool PlatformAdapter_getGPUFamily(char** outValue) {
    @autoreleasepool {
        if (!outValue) return false;
        *outValue = NULL;
        
        @try {
            // All iOS/macOS devices use Apple's custom GPUs
            *outValue = strdup("apple");
            return *outValue != NULL;
        } @catch (NSException* exception) {
            return false;
        }
    }
}

/**
 * Check if device is a tablet
 * Uses UIDevice.userInterfaceIdiom to determine form factor
 * Matches Swift SDK: device.userInterfaceIdiom == .pad
 */
bool PlatformAdapter_isTablet(void) {
    @autoreleasepool {
        @try {
            UIUserInterfaceIdiom idiom = [[UIDevice currentDevice] userInterfaceIdiom];
            return idiom == UIUserInterfaceIdiomPad;
        } @catch (NSException* exception) {
            NSLog(@"[PlatformAdapterBridge] isTablet exception: %@", exception);
            return false;
        }
    }
}

// ============================================================================
// HTTP Download (Async Platform Adapter Fallback)
// ============================================================================

int PlatformAdapter_httpDownload(
    const char* url,
    const char* destinationPath,
    const char* taskId
) {
    @autoreleasepool {
        if (!url || !destinationPath || !taskId) {
            return RAC_ERROR_INVALID_PARAMETER;
        }

        NSString* urlStr = [NSString stringWithUTF8String:url];
        NSString* destStr = [NSString stringWithUTF8String:destinationPath];
        NSString* taskStr = [NSString stringWithUTF8String:taskId];

        if (!urlStr || !destStr || !taskStr) {
            return RAC_ERROR_INVALID_PARAMETER;
        }

        return [[RunAnywhereHttpDownloadManager shared] startDownload:urlStr
                                                          destination:destStr
                                                               taskId:taskStr];
    }
}

bool PlatformAdapter_httpDownloadCancel(const char* taskId) {
    @autoreleasepool {
        if (!taskId) {
            return false;
        }

        NSString* taskStr = [NSString stringWithUTF8String:taskId];
        if (!taskStr) {
            return false;
        }

        return [[RunAnywhereHttpDownloadManager shared] cancelDownload:taskStr];
    }
}

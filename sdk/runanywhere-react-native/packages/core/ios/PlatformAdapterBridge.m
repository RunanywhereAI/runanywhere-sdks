/**
 * PlatformAdapterBridge.m
 *
 * C bridge to call Swift PlatformAdapter/KeychainManager from C++.
 * This bridge is necessary because C++ cannot directly call Swift code.
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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

// ============================================================================
// HTTP POST for Device Registration (Synchronous)
// Matches Swift's CppBridge+Device.swift http_post callback
// ============================================================================

/**
 * Synchronous HTTP POST for device registration
 * Called from C++ device manager callbacks
 *
 * @param url Full URL to POST to
 * @param jsonBody JSON body string
 * @param supabaseKey Supabase API key (for dev mode, can be NULL)
 * @param outStatusCode Pointer to store HTTP status code
 * @param outResponseBody Pointer to store response body (must be freed by caller)
 * @param outErrorMessage Pointer to store error message (must be freed by caller)
 * @return true if request succeeded (2xx or 409)
 */
bool PlatformAdapter_httpPostSync(
    const char* url,
    const char* jsonBody,
    const char* supabaseKey,
    int* outStatusCode,
    char** outResponseBody,
    char** outErrorMessage
) {
    @autoreleasepool {
        if (!url || !jsonBody || !outStatusCode) {
            if (outErrorMessage) *outErrorMessage = strdup("Invalid arguments");
            return false;
        }

        *outStatusCode = 0;
        if (outResponseBody) *outResponseBody = NULL;
        if (outErrorMessage) *outErrorMessage = NULL;

        NSString* urlStr = [NSString stringWithUTF8String:url];
        NSString* bodyStr = [NSString stringWithUTF8String:jsonBody];
        NSString* apiKey = supabaseKey ? [NSString stringWithUTF8String:supabaseKey] : nil;

        if (!urlStr || !bodyStr) {
            if (outErrorMessage) *outErrorMessage = strdup("Invalid URL or body");
            return false;
        }

        NSURL* nsUrl = [NSURL URLWithString:urlStr];
        if (!nsUrl) {
            if (outErrorMessage) *outErrorMessage = strdup("Invalid URL format");
            return false;
        }

        NSLog(@"[PlatformAdapterBridge] HTTP POST to: %@", urlStr);

        // For Supabase device registration, add ?on_conflict=device_id for UPSERT
        // This matches Swift's HTTPService.swift logic
        if ([urlStr containsString:@"/rest/v1/sdk_devices"]) {
            if (![urlStr containsString:@"on_conflict="]) {
                NSString* separator = [urlStr containsString:@"?"] ? @"&" : @"?";
                urlStr = [NSString stringWithFormat:@"%@%@on_conflict=device_id", urlStr, separator];
                nsUrl = [NSURL URLWithString:urlStr];
                NSLog(@"[PlatformAdapterBridge] Added on_conflict for UPSERT: %@", urlStr);
            }
        }

        // Create request
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsUrl];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
        request.timeoutInterval = 30.0;

        // Headers
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

        // Supabase headers (for device registration UPSERT)
        if (apiKey) {
            [request setValue:apiKey forHTTPHeaderField:@"apikey"];
            [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
            [request setValue:@"resolution=merge-duplicates" forHTTPHeaderField:@"Prefer"];
        }

        // Synchronous request using semaphore (like Swift SDK)
        __block NSData* responseData = nil;
        __block NSHTTPURLResponse* httpResponse = nil;
        __block NSError* error = nil;

        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        NSURLSessionDataTask* task = [[NSURLSession sharedSession]
            dataTaskWithRequest:request
            completionHandler:^(NSData* data, NSURLResponse* response, NSError* err) {
                responseData = data;
                httpResponse = (NSHTTPURLResponse*)response;
                error = err;
                dispatch_semaphore_signal(semaphore);
            }];

        [task resume];

        // Wait with 30 second timeout
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC);
        long result = dispatch_semaphore_wait(semaphore, timeout);

        if (result != 0) {
            if (outErrorMessage) *outErrorMessage = strdup("Request timed out");
            NSLog(@"[PlatformAdapterBridge] HTTP POST timed out");
            return false;
        }

        if (error) {
            if (outErrorMessage) *outErrorMessage = strdup([[error localizedDescription] UTF8String]);
            NSLog(@"[PlatformAdapterBridge] HTTP POST error: %@", error);
            return false;
        }

        *outStatusCode = (int)httpResponse.statusCode;

        // Store response body
        if (responseData && outResponseBody) {
            NSString* bodyString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
            if (bodyString) {
                *outResponseBody = strdup([bodyString UTF8String]);
            }
        }

        // 2xx or 409 (conflict/already exists) = success for device registration
        BOOL isSuccess = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) ||
                         httpResponse.statusCode == 409;

        // Log response body for debugging (especially on errors)
        NSString* responseBodyStr = nil;
        if (responseData) {
            responseBodyStr = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        }
        
        if (!isSuccess) {
            NSLog(@"[PlatformAdapterBridge] HTTP POST failed with status=%ld, response: %@",
                  (long)httpResponse.statusCode, responseBodyStr ?: @"(empty)");
            if (outErrorMessage) {
                NSString* errorMsg = [NSString stringWithFormat:@"HTTP %ld: %@", 
                    (long)httpResponse.statusCode, responseBodyStr ?: @"Unknown error"];
                *outErrorMessage = strdup([errorMsg UTF8String]);
            }
        }

        NSLog(@"[PlatformAdapterBridge] HTTP POST completed: status=%d success=%d",
              *outStatusCode, isSuccess);

        return isSuccess;
    }
}


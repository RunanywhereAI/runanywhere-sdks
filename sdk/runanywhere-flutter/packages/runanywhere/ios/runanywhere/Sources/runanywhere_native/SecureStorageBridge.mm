// SPDX-License-Identifier: Apache-2.0

// Synchronous Keychain bridge for Dart FFI secure-storage callbacks.
//
// Plugin storage APIs are async at the Dart boundary, while the commons
// platform/auth vtables require a synchronous result. These helpers perform
// Keychain operations directly and only return RAC_SUCCESS after SecItem has
// completed, so Dart never acknowledges a queued persistence operation.

#import <Foundation/Foundation.h>
#import <Security/Security.h>

#include <cstdint>
#include <cstring>

namespace {

constexpr int32_t RAC_SUCCESS = 0;
constexpr int32_t RAC_ERROR_FILE_NOT_FOUND = -183;
constexpr int32_t RAC_ERROR_INVALID_ARGUMENT = -259;
constexpr int32_t RAC_ERROR_BUFFER_TOO_SMALL = -261;
constexpr int32_t RAC_ERROR_SECURE_STORAGE_FAILED = -333;

NSString* const kRunAnywhereKeychainService = @"com.runanywhere.sdk";

NSDictionary* keychain_query(NSString* key) {
    return @{
        (__bridge NSString*)kSecClass : (__bridge NSString*)kSecClassGenericPassword,
        (__bridge NSString*)kSecAttrService : kRunAnywhereKeychainService,
        (__bridge NSString*)kSecAttrAccount : key,
        (__bridge NSString*)kSecAttrSynchronizable : @NO,
        (__bridge NSString*)kSecAttrAccessible :
            (__bridge NSString*)kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    };
}

}  // namespace

extern "C" {

__attribute__((visibility("default"), used)) int32_t
ra_flutter_secure_storage_store(const char* key, const char* value) {
    if (!key || !value) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    @autoreleasepool {
        NSString* key_string = [NSString stringWithUTF8String:key];
        NSString* value_string = [NSString stringWithUTF8String:value];
        NSData* value_data = [value_string dataUsingEncoding:NSUTF8StringEncoding];
        if (!key_string || !value_string || !value_data) {
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }

        NSDictionary* query = keychain_query(key_string);
        NSDictionary* update = @{(__bridge NSString*)kSecValueData : value_data};
        OSStatus status =
            SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
        if (status == errSecItemNotFound) {
            NSMutableDictionary* add = [query mutableCopy];
            [add addEntriesFromDictionary:update];
            status = SecItemAdd((__bridge CFDictionaryRef)add, nullptr);
        }
        return status == errSecSuccess ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
    }
}

__attribute__((visibility("default"), used)) int32_t
ra_flutter_secure_storage_retrieve(const char* key, char* out_value, size_t buffer_size) {
    if (!key || !out_value || buffer_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_value[0] = '\0';

    @autoreleasepool {
        NSString* key_string = [NSString stringWithUTF8String:key];
        if (!key_string) {
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }

        NSMutableDictionary* query = [keychain_query(key_string) mutableCopy];
        query[(__bridge NSString*)kSecReturnData] = @YES;
        query[(__bridge NSString*)kSecMatchLimit] = (__bridge NSString*)kSecMatchLimitOne;

        CFTypeRef raw_result = nullptr;
        const OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &raw_result);
        if (status == errSecItemNotFound) {
            return RAC_ERROR_FILE_NOT_FOUND;
        }
        if (status != errSecSuccess || !raw_result ||
            CFGetTypeID(raw_result) != CFDataGetTypeID()) {
            if (raw_result) CFRelease(raw_result);
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }

        NSData* data = CFBridgingRelease(raw_result);
        if (data.length == 0) {
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }
        if (data.length + 1 > buffer_size) {
            return RAC_ERROR_BUFFER_TOO_SMALL;
        }
        if (![[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) {
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }

        std::memcpy(out_value, data.bytes, data.length);
        out_value[data.length] = '\0';
        return static_cast<int32_t>(data.length);
    }
}

__attribute__((visibility("default"), used)) int32_t
ra_flutter_secure_storage_delete(const char* key) {
    if (!key) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    @autoreleasepool {
        NSString* key_string = [NSString stringWithUTF8String:key];
        if (!key_string) {
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }
        const OSStatus status = SecItemDelete((__bridge CFDictionaryRef)keychain_query(key_string));
        return status == errSecSuccess || status == errSecItemNotFound
                   ? RAC_SUCCESS
                   : RAC_ERROR_SECURE_STORAGE_FAILED;
    }
}

}  // extern "C"

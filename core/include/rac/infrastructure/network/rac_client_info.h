/**
 * @file rac_client_info.h
 * @brief SDK client/application metadata shared by telemetry and device APIs.
 */

#ifndef RAC_CLIENT_INFO_H
#define RAC_CLIENT_INFO_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Metadata about the SDK binding and host application.
 *
 * `platform` remains the OS family ("ios", "android", "web", ...). The SDK
 * binding/client type ("swift", "kotlin", "flutter", "react-native", "web",
 * "cli") lives here so analytics can distinguish app platform from SDK wrapper
 * without overloading one string.
 */
typedef struct rac_client_info {
    const char* sdk_binding;     // "swift", "kotlin", "flutter", "react-native", "web", "cli"
    const char* app_identifier;  // Bundle id, application id, package name, origin, or CLI id
    const char* app_name;        // Display/application name when available
    const char* app_version;     // User-visible app version
    const char* app_build;       // Build number/version code when available
    const char* locale;          // BCP-47 locale/language tag when available
    const char* timezone;        // IANA timezone id when available
} rac_client_info_t;

#ifdef __cplusplus
}
#endif

#endif  // RAC_CLIENT_INFO_H

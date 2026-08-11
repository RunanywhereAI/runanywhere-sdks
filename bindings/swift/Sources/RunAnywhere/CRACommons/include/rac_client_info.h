/**
 * @file rac_client_info.h
 * @brief SDK client/application metadata shared by telemetry and device APIs.
 */

#ifndef RAC_CLIENT_INFO_H
#define RAC_CLIENT_INFO_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_client_info {
    const char* sdk_binding;
    const char* app_identifier;
    const char* app_name;
    const char* app_version;
    const char* app_build;
    const char* locale;
    const char* timezone;
} rac_client_info_t;

#ifdef __cplusplus
}
#endif

#endif  // RAC_CLIENT_INFO_H

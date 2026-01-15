/**
 * @file rac_telemetry_manager.h
 * @brief Telemetry manager - handles event queuing, batching, and serialization
 *
 * C++ handles all telemetry logic:
 * - Convert analytics events to telemetry payloads
 * - Queue and batch events
 * - Group by modality for production
 * - Serialize to JSON (environment-aware)
 * - Callback to platform SDK for HTTP calls
 *
 * Platform SDKs only need to:
 * - Provide device info
 * - Make HTTP calls when callback is invoked
 */

#ifndef RAC_TELEMETRY_MANAGER_H
#define RAC_TELEMETRY_MANAGER_H

#include <RACommons/rac_analytics_events.h>
#include <RACommons/rac_types.h>
#include <RACommons/rac_environment.h>
#include <RACommons/rac_telemetry_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TELEMETRY MANAGER
// =============================================================================

/**
 * @brief Opaque telemetry manager handle
 */
typedef struct rac_telemetry_manager rac_telemetry_manager_t;

/**
 * @brief HTTP request callback from C++ to platform SDK
 *
 * C++ builds the JSON and determines the endpoint.
 * Platform SDK just makes the HTTP call.
 *
 * @param user_data User data provided at registration
 * @param endpoint The API endpoint path (e.g., "/api/v1/sdk/telemetry")
 * @param json_body The JSON request body (null-terminated string)
 * @param json_length Length of JSON body
 * @param requires_auth Whether request needs authentication
 */
typedef void (*rac_telemetry_http_callback_t)(void* user_data, const char* endpoint,
                                              const char* json_body, size_t json_length,
                                              rac_bool_t requires_auth);

/**
 * @brief HTTP response callback from platform SDK to C++
 *
 * Platform SDK calls this after HTTP completes.
 *
 * @param manager The telemetry manager
 * @param success Whether HTTP call succeeded
 * @param response_json Response JSON (can be NULL on failure)
 * @param error_message Error message if failed (can be NULL)
 */
RAC_API void rac_telemetry_manager_http_complete(rac_telemetry_manager_t* manager,
                                                 rac_bool_t success, const char* response_json,
                                                 const char* error_message);

// =============================================================================
// LIFECYCLE
// =============================================================================

/**
 * @brief Create telemetry manager
 *
 * @param env SDK environment (determines endpoint and encoding)
 * @param device_id Persistent device UUID (from Keychain)
 * @param platform Platform string ("ios", "android", etc.)
 * @param sdk_version SDK version string
 * @return Manager handle or NULL on failure
 */
RAC_API rac_telemetry_manager_t* rac_telemetry_manager_create(rac_environment_t env,
                                                              const char* device_id,
                                                              const char* platform,
                                                              const char* sdk_version);

/**
 * @brief Destroy telemetry manager
 */
RAC_API void rac_telemetry_manager_destroy(rac_telemetry_manager_t* manager);

/**
 * @brief Set device info for telemetry payloads
 *
 * Call this after creating the manager to set device details.
 */
RAC_API void rac_telemetry_manager_set_device_info(rac_telemetry_manager_t* manager,
                                                   const char* device_model,
                                                   const char* os_version);

/**
 * @brief Register HTTP callback
 *
 * Platform SDK must register this to receive HTTP requests.
 */
RAC_API void rac_telemetry_manager_set_http_callback(rac_telemetry_manager_t* manager,
                                                     rac_telemetry_http_callback_t callback,
                                                     void* user_data);

// =============================================================================
// EVENT TRACKING
// =============================================================================

/**
 * @brief Track a telemetry payload directly
 *
 * Queues the payload for batching and sending.
 */
RAC_API rac_result_t rac_telemetry_manager_track(rac_telemetry_manager_t* manager,
                                                 const rac_telemetry_payload_t* payload);

/**
 * @brief Track from analytics event data
 *
 * Converts analytics event to telemetry payload and queues it.
 */
RAC_API rac_result_t rac_telemetry_manager_track_analytics(rac_telemetry_manager_t* manager,
                                                           rac_event_type_t event_type,
                                                           const rac_analytics_event_data_t* data);

/**
 * @brief Flush queued events immediately
 *
 * Sends all queued events to the backend.
 */
RAC_API rac_result_t rac_telemetry_manager_flush(rac_telemetry_manager_t* manager);

// =============================================================================
// JSON SERIALIZATION
// =============================================================================

/**
 * @brief Serialize telemetry payload to JSON
 *
 * @param payload The payload to serialize
 * @param env Environment (affects field names and which fields to include)
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @param out_length Output: Length of JSON string
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_telemetry_manager_payload_to_json(const rac_telemetry_payload_t* payload,
                                                           rac_environment_t env, char** out_json,
                                                           size_t* out_length);

/**
 * @brief Serialize batch request to JSON
 *
 * @param request The batch request
 * @param env Environment
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @param out_length Output: Length of JSON string
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t
rac_telemetry_manager_batch_to_json(const rac_telemetry_batch_request_t* request,
                                    rac_environment_t env, char** out_json, size_t* out_length);

/**
 * @brief Parse batch response from JSON
 *
 * @param json JSON response string
 * @param out_response Output: Parsed response (caller must free)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_telemetry_manager_parse_response(
    const char* json, rac_telemetry_batch_response_t* out_response);

// =============================================================================
// DEVICE REGISTRATION
// =============================================================================

/**
 * @brief Serialize device registration request to JSON
 *
 * @param request The registration request
 * @param env Environment
 * @param out_json Output: JSON string (caller must free with rac_free)
 * @param out_length Output: Length of JSON string
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t
rac_device_registration_to_json(const rac_device_registration_request_t* request,
                                rac_environment_t env, char** out_json, size_t* out_length);

/**
 * @brief Get device registration endpoint for environment
 *
 * @param env Environment
 * @return Endpoint path string (static, do not free)
 */
RAC_API const char* rac_device_registration_endpoint(rac_environment_t env);

#ifdef __cplusplus
}
#endif

#endif  // RAC_TELEMETRY_MANAGER_H

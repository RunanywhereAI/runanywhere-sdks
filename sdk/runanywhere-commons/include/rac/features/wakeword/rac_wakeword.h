/**
 * @file rac_wakeword.h
 * @brief RunAnywhere Commons - Wake Word Detection (Combined Header)
 *
 * Single include for all wake word detection functionality.
 *
 * Features:
 * - Wake word detection using openWakeWord ONNX models
 * - Optional VAD pre-filtering using Silero VAD
 * - Multiple simultaneous wake words
 * - Configurable thresholds and callbacks
 *
 * Example:
 * @code
 * #include <rac/features/wakeword/rac_wakeword.h>
 *
 * // Detection callback
 * void on_wakeword(const rac_wakeword_event_t* event, void* user_data) {
 *     printf("Wake word detected: %s (confidence: %.2f)\n",
 *            event->keyword_name, event->confidence);
 * }
 *
 * int main() {
 *     rac_handle_t wakeword;
 *     rac_wakeword_create(&wakeword);
 *
 *     rac_wakeword_config_t config = RAC_WAKEWORD_CONFIG_DEFAULT;
 *     rac_wakeword_initialize(wakeword, &config);
 *
 *     // Load VAD for pre-filtering
 *     rac_wakeword_load_vad(wakeword, "silero_vad.onnx");
 *
 *     // Load wake word models
 *     rac_wakeword_load_model(wakeword, "hey_jarvis.onnx", "jarvis", "Hey Jarvis");
 *
 *     // Set callback
 *     rac_wakeword_set_callback(wakeword, on_wakeword, NULL);
 *
 *     // Start listening
 *     rac_wakeword_start(wakeword);
 *
 *     // Process audio frames in your audio callback
 *     // rac_wakeword_process(wakeword, samples, num_samples, NULL);
 *
 *     // Cleanup
 *     rac_wakeword_stop(wakeword);
 *     rac_wakeword_destroy(wakeword);
 * }
 * @endcode
 */

#ifndef RAC_WAKEWORD_H
#define RAC_WAKEWORD_H

#include "rac/features/wakeword/rac_wakeword_types.h"
#include "rac/features/wakeword/rac_wakeword_service.h"

#endif /* RAC_WAKEWORD_H */

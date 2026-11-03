/** @file rac_test_logger.cpp
 * No-op logger for isolated production registry/loader tests.
 */
#include "rac/core/rac_logger.h"

extern "C" {
rac_log_level_t rac_logger_get_min_level(void) {
    return RAC_LOG_FATAL;
}
void rac_logger_logf(rac_log_level_t, const char*, const rac_log_metadata_t*, const char*, ...) {}
}

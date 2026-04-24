/**
 * @file rac_extraction_stub.cpp
 * @brief Stub archive extraction implementation when native extraction is disabled.
 */

#include "rac/infrastructure/extraction/rac_extraction.h"

#include "rac/core/rac_logger.h"

static const char* kLogTag = "Extraction";

extern "C" {

rac_result_t rac_extract_archive_native(const char* archive_path, const char* destination_dir,
                                        const rac_extraction_options_t* options,
                                        rac_extraction_progress_fn progress_callback,
                                        void* user_data, rac_extraction_result_t* out_result) {
    (void)archive_path;
    (void)destination_dir;
    (void)options;
    (void)progress_callback;
    (void)user_data;
    if (out_result) {
        *out_result = {0, 0, 0, 0};
    }
    RAC_LOG_WARNING(kLogTag,
                    "Native archive extraction is disabled in this build");
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_bool_t rac_detect_archive_type(const char* file_path, rac_archive_type_t* out_type) {
    (void)file_path;
    if (out_type) {
        *out_type = RAC_ARCHIVE_TYPE_NONE;
    }
    return RAC_FALSE;
}

}

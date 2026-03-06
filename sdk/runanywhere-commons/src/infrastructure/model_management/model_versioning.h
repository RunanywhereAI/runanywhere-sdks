#ifndef RAC_MODEL_VERSIONING_H
#define RAC_MODEL_VERSIONING_H

#include <string>
std::string rac_generate_deterministic_version(const char* download_url);
#include "rac/infrastructure/model_management/rac_model_types.h"

std::string rac_generate_versioned_model_id(const char* model_id,
                                            const char* version);

rac_bool_t rac_model_version_matches(const char* versioned_id,
                                     const char* expected_version);

std::string rac_extract_base_model_id(const char* versioned_id);

std::string rac_extract_version(const char* versioned_id);

#endif
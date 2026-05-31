#pragma once

#include "rac/core/rac_error.h"

#if defined(__OBJC__)
#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

MLModelConfiguration* rac_coreml_default_model_configuration(void);

/**
 * @brief Load a CoreML model bundle from `<dir>/<name>.mlmodelc`.
 *
 * The runtime is built under manual retain/release (MRC) semantics. To make
 * the ownership boundary explicit at the helper, callers receive a
 * *retained* MLModel (NS_RETURNS_RETAINED). The caller is responsible for
 * sending `-release` to the returned object when it is no longer needed,
 * which keeps the pointer alive across enclosing @autoreleasepool drains —
 * the exact scenario that previously left long-lived engine state holding
 * dangling MLModel pointers (runtimes-001).
 *
 * Returns `nil` on missing/failed load; nil returns require no release.
 */
MLModel* rac_coreml_load_model_in_dir(NSString* dir, NSString* name, bool required,
                                      const char* log_category) NS_RETURNS_RETAINED;
bool rac_coreml_file_exists(NSString* path);
NSString* rac_coreml_find_resource_dir(NSString* base_dir, NSString* required_model_name);
#endif

extern "C" {

rac_result_t rac_coreml_runtime_require_available(void);
}

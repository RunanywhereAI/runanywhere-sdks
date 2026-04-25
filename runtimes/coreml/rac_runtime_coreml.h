#pragma once

#include "rac/core/rac_error.h"

#if defined(__OBJC__)
#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

MLModelConfiguration* rac_coreml_default_model_configuration(void);
MLModel* rac_coreml_load_model_in_dir(NSString* dir,
                                      NSString* name,
                                      bool required,
                                      const char* log_category);
bool rac_coreml_file_exists(NSString* path);
NSString* rac_coreml_find_resource_dir(NSString* base_dir, NSString* required_model_name);
#endif

extern "C" {

rac_result_t rac_coreml_runtime_require_available(void);

}

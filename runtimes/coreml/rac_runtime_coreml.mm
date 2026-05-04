#include "rac_runtime_coreml.h"

#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#include <new>

#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace {

constexpr const char* kLogCat = "Runtime.CoreML";

const rac_device_class_t k_supported_devices[] = {
    RAC_DEVICE_CLASS_CPU,
    RAC_DEVICE_CLASS_GPU,
    RAC_DEVICE_CLASS_NPU,
};
const uint32_t k_supported_formats[] = {
    5,  // MODEL_FORMAT_COREML
    6,  // MODEL_FORMAT_COREML
    8,  // MODEL_FORMAT_MLPACKAGE
};
const rac_primitive_t k_supported_primitives[] = {
    RAC_PRIMITIVE_TRANSCRIBE,
    RAC_PRIMITIVE_DIFFUSION,
    RAC_PRIMITIVE_EMBED,
};

struct CoreMLSession {
    MLModel* model = nil;
};

rac_result_t coreml_init(void) {
    Class model_class = NSClassFromString(@"MLModel");
    return model_class != Nil ? RAC_SUCCESS : RAC_ERROR_CAPABILITY_UNSUPPORTED;
}

void coreml_destroy(void) {}

rac_result_t coreml_create_session(const rac_runtime_session_desc_t* desc,
                                   rac_runtime_session_t** out) {
    if (!desc || !out) return RAC_ERROR_NULL_POINTER;
    *out = nullptr;
    if (!desc->model_path || desc->model_path[0] == '\0') {
        return RAC_ERROR_INVALID_PARAMETER;
    }

    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:desc->model_path];
        if (!rac_coreml_file_exists(path)) {
            return RAC_ERROR_MODEL_NOT_FOUND;
        }
        NSError* err = nil;
        MLModelConfiguration* cfg = rac_coreml_default_model_configuration();
        MLModel* model = [MLModel modelWithContentsOfURL:[NSURL fileURLWithPath:path]
                                           configuration:cfg
                                                   error:&err];
        if (!model) {
            RAC_LOG_ERROR(kLogCat,
                          "CoreML create_session failed (%s): %s",
                          desc->model_path,
                          err ? [[err localizedDescription] UTF8String] : "unknown");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        auto* session = new (std::nothrow) CoreMLSession();
        if (!session) return RAC_ERROR_OUT_OF_MEMORY;
        session->model = model;
        *out = reinterpret_cast<rac_runtime_session_t*>(session);
        return RAC_SUCCESS;
    }
}

void coreml_destroy_session(rac_runtime_session_t* session) {
    delete reinterpret_cast<CoreMLSession*>(session);
}

rac_result_t coreml_device_info(rac_runtime_device_info_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_NPU;
    out->device_id = "apple-coreml";
    out->display_name = "Apple Core ML";
    return RAC_SUCCESS;
}

rac_result_t coreml_capabilities(rac_runtime_capabilities_t* out) {
    if (!out) return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    out->capability_flags = RAC_RUNTIME_CAP_FP16 | RAC_RUNTIME_CAP_DYNAMIC_SHAPES;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    // Capability shrunk: run_session is NULL; declare zero primitives until tensor execution path lands.
    out->supported_primitives = nullptr;
    out->supported_primitives_count = 0;
    return RAC_SUCCESS;
}

const rac_runtime_vtable_t k_coreml_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_COREML,
        /* .name                    = */ "coreml",
        /* .display_name            = */ "Apple Core ML",
        /* .version                 = */ nullptr,
        /* .priority                = */ 90,
        /* .supported_formats       = */ k_supported_formats,
        /* .supported_formats_count = */ sizeof(k_supported_formats) / sizeof(k_supported_formats[0]),
        /* .supported_devices       = */ k_supported_devices,
        /* .supported_devices_count = */ sizeof(k_supported_devices) / sizeof(k_supported_devices[0]),
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ coreml_init,
    /* .destroy         = */ coreml_destroy,
    /* .create_session  = */ coreml_create_session,
    /* .run_session     = */ nullptr,
    /* .destroy_session = */ coreml_destroy_session,
    /* .alloc_buffer    = */ nullptr,
    /* .free_buffer     = */ nullptr,
    /* .device_info     = */ coreml_device_info,
    /* .capabilities    = */ coreml_capabilities,
    /* .reserved_slot_0 = */ nullptr,
    /* .reserved_slot_1 = */ nullptr,
    /* .reserved_slot_2 = */ nullptr,
    /* .reserved_slot_3 = */ nullptr,
    /* .reserved_slot_4 = */ nullptr,
    /* .reserved_slot_5 = */ nullptr,
};

}  // namespace

MLModelConfiguration* rac_coreml_default_model_configuration(void) {
    MLModelConfiguration* cfg = [[MLModelConfiguration alloc] init];
    cfg.computeUnits = MLComputeUnitsAll;
    return cfg;
}

bool rac_coreml_file_exists(NSString* path) {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

NSString* rac_coreml_find_resource_dir(NSString* base_dir, NSString* required_model_name) {
    NSString* model_name = required_model_name ?: @"Unet";
    NSString* direct_model = [base_dir stringByAppendingPathComponent:
                                [model_name stringByAppendingString:@".mlmodelc"]];
    if (rac_coreml_file_exists(direct_model)) {
        return base_dir;
    }

    NSArray<NSURL*>* contents =
        [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:base_dir]
                                      includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                         options:0
                                                           error:nil];
    for (NSURL* item in contents) {
        NSNumber* is_dir = nil;
        [item getResourceValue:&is_dir forKey:NSURLIsDirectoryKey error:nil];
        if (![is_dir boolValue]) {
            continue;
        }
        NSString* nested_model =
            [[item path] stringByAppendingPathComponent:
                [model_name stringByAppendingString:@".mlmodelc"]];
        if (rac_coreml_file_exists(nested_model)) {
            return [item path];
        }
    }
    return base_dir;
}

MLModel* rac_coreml_load_model_in_dir(NSString* dir,
                                      NSString* name,
                                      bool required,
                                      const char* log_category) {
    NSString* path = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".mlmodelc"]];
    NSURL* url = [NSURL fileURLWithPath:path];
    const char* category = log_category ? log_category : kLogCat;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (required) {
            RAC_LOG_ERROR(category, "Required MLModel missing: %s", [path UTF8String]);
        }
        return nil;
    }

    NSError* err = nil;
    MLModelConfiguration* cfg = rac_coreml_default_model_configuration();
    MLModel* model = [MLModel modelWithContentsOfURL:url configuration:cfg error:&err];
    if (!model) {
        RAC_LOG_ERROR(category,
                      "MLModel load failed (%s): %s",
                      [name UTF8String],
                      err ? [[err localizedDescription] UTF8String] : "unknown");
        return nil;
    }
    return model;
}

extern "C" rac_result_t rac_coreml_runtime_require_available(void) {
    return rac_runtime_get_by_id(RAC_RUNTIME_COREML) != nullptr
               ? RAC_SUCCESS
               : RAC_ERROR_BACKEND_UNAVAILABLE;
}

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_coreml(void) {
    return &k_coreml_vtable;
}

RAC_STATIC_RUNTIME_REGISTER(coreml);

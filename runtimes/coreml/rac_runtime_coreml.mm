#include "rac_runtime_coreml.h"

#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>

#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_model_format_ids.h"
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
    RAC_MODEL_FORMAT_ID_COREML,
    RAC_MODEL_FORMAT_ID_MLMODEL,
    RAC_MODEL_FORMAT_ID_MLPACKAGE,
};

rac_result_t coreml_init(void) {
    // NSClassFromString(@"MLModel") only proves the framework is linked, which
    // is true on every host where this TU is compiled in -- so the registry
    // would accept CoreML on iOS Simulator x86_64 / older OSes that cannot
    // actually run a CoreML graph. Mirror Metal's pattern and probe a real
    // CoreML object: if MLModelConfiguration cannot be instantiated the runtime
    // cannot run, so self-reject at registry time and let the router fall back
    // to ONNX/llamacpp paths.
    //
    // Any NSException raised by Foundation/CoreML must be caught here -- this is
    // the first .mm entry on the C registry path and an uncaught ObjC exception
    // bridging into extern "C" aborts the process.
    @autoreleasepool {
        @try {
            MLModelConfiguration* cfg = [[[MLModelConfiguration alloc] init] autorelease];
            if (cfg == nil) {
                return RAC_ERROR_CAPABILITY_UNSUPPORTED;
            }
            cfg.computeUnits = MLComputeUnitsAll;
        } @catch (NSException* e) {
            RAC_LOG_ERROR(kLogCat, "CoreML init raised %s: %s",
                          e.name ? [e.name UTF8String] : "NSException",
                          e.reason ? [e.reason UTF8String] : "no reason");
            return RAC_ERROR_CAPABILITY_UNSUPPORTED;
        }
    }
    return RAC_SUCCESS;
}

void coreml_destroy(void) {}

rac_result_t coreml_device_info(rac_runtime_device_info_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_device_info_t{};
    out->device_class = RAC_DEVICE_CLASS_NPU;
    out->device_id = "apple-coreml";
    out->display_name = "Apple Core ML";
    return RAC_SUCCESS;
}

rac_result_t coreml_capabilities(rac_runtime_capabilities_t* out) {
    if (!out)
        return RAC_ERROR_NULL_POINTER;
    *out = rac_runtime_capabilities_t{};
    out->capability_flags = RAC_RUNTIME_CAP_FP16 | RAC_RUNTIME_CAP_DYNAMIC_SHAPES;
    out->supported_formats = k_supported_formats;
    out->supported_formats_count = sizeof(k_supported_formats) / sizeof(k_supported_formats[0]);
    // CoreML is a capability + loader-helper runtime: it advertises device
    // presence/formats for routing and exposes MLModel loader helpers that
    // engines (diffusion-coreml) call directly. It is NOT a session-execution
    // runtime -- the session/run/tensor vtable slots are NULL and
    // RAC_RUNTIME_CAP_SESSION_EXECUTION is intentionally not set -- so it
    // declares zero execution primitives.
    out->supported_primitives = nullptr;
    out->supported_primitives_count = 0;
    return RAC_SUCCESS;
}

const rac_runtime_vtable_v2_t k_coreml_vtable_v2 = {
    /* .abi_version    = */ RAC_RUNTIME_ABI_VERSION_V2,
    /* .struct_size    = */ sizeof(rac_runtime_vtable_v2_t),
    /* .run_session_v2 = */ nullptr,
    /* .alloc_buffer   = */ nullptr,
    /* .buffer_info    = */ nullptr,
    /* .map_buffer     = */ nullptr,
    /* .unmap_buffer   = */ nullptr,
    /* .copy_buffer    = */ nullptr,
    /* .release_tensor = */ nullptr,
    /* .reserved_0     = */ nullptr,
    /* .reserved_1     = */ nullptr,
    /* .reserved_2     = */ nullptr,
    /* .reserved_3     = */ nullptr,
    /* .reserved_4     = */ nullptr,
    /* .reserved_5     = */ nullptr,
    /* .reserved_6     = */ nullptr,
    /* .reserved_7     = */ nullptr,
};

const rac_runtime_vtable_t k_coreml_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_COREML,
        /* .name                    = */ "coreml",
        /* .display_name            = */ "Apple Core ML",
        /* .version                 = */ nullptr,
        /* .priority                = */ 90,
        /* .supported_formats       = */ k_supported_formats,
        /* .supported_formats_count = */ sizeof(k_supported_formats) /
            sizeof(k_supported_formats[0]),
        /* .supported_devices       = */ k_supported_devices,
        /* .supported_devices_count = */ sizeof(k_supported_devices) /
            sizeof(k_supported_devices[0]),
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ coreml_init,
    /* .destroy         = */ coreml_destroy,
    /* .create_session  = */ nullptr,
    /* .run_session     = */ nullptr,
    /* .destroy_session = */ nullptr,
    /* .alloc_buffer    = */ nullptr,
    /* .free_buffer     = */ nullptr,
    /* .device_info     = */ coreml_device_info,
    /* .capabilities    = */ coreml_capabilities,
    /* .reserved_slot_0 = */ &k_coreml_vtable_v2,
    /* .reserved_slot_1 = */ nullptr,
    /* .reserved_slot_2 = */ nullptr,
    /* .reserved_slot_3 = */ nullptr,
    /* .reserved_slot_4 = */ nullptr,
    /* .reserved_slot_5 = */ nullptr,
};

}  // namespace

MLModelConfiguration* rac_coreml_default_model_configuration(void) {
    // Return an autoreleased instance so MRC callers don't leak it on
    // error paths (clang-analyzer-osx.cocoa.RetainCount).
    //
    // -[MLModelConfiguration init] is documented to raise on
    // OOM / framework misconfiguration; convert to a nil return so the C ABI
    // boundary stays exception-free.
    @try {
        MLModelConfiguration* cfg = [[[MLModelConfiguration alloc] init] autorelease];
        cfg.computeUnits = MLComputeUnitsAll;
        return cfg;
    } @catch (NSException* e) {
        RAC_LOG_ERROR(kLogCat, "MLModelConfiguration init raised %s: %s",
                      e.name ? [e.name UTF8String] : "NSException",
                      e.reason ? [e.reason UTF8String] : "no reason");
        return nil;
    }
}

bool rac_coreml_file_exists(NSString* path) {
    if (!path)
        return false;
    // NSFileManager fileExistsAtPath: shouldn't raise on a valid
    // NSString, but a programmatic NSGenericException from a swizzled file
    // manager (e.g. MDM agents on enterprise iOS) must not bubble up.
    @try {
        return [[NSFileManager defaultManager] fileExistsAtPath:path];
    } @catch (NSException* e) {
        RAC_LOG_ERROR(kLogCat, "NSFileManager fileExistsAtPath raised %s: %s",
                      e.name ? [e.name UTF8String] : "NSException",
                      e.reason ? [e.reason UTF8String] : "no reason");
        return false;
    }
}

NSString* rac_coreml_find_resource_dir(NSString* base_dir, NSString* required_model_name) {
    NSString* model_name = required_model_name ?: @"Unet";
    // Directory enumeration touches the filesystem and can raise
    // on permission errors / sandbox extensions. Fall back to base_dir on any
    // exception so the caller still gets a usable (if pessimistic) path.
    @try {
        NSString* direct_model = [base_dir
            stringByAppendingPathComponent:[model_name stringByAppendingString:@".mlmodelc"]];
        if (rac_coreml_file_exists(direct_model)) {
            return base_dir;
        }

        NSArray<NSURL*>* contents = [[NSFileManager defaultManager]
              contentsOfDirectoryAtURL:[NSURL fileURLWithPath:base_dir]
            includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                               options:0
                                 error:nil];
        for (NSURL* item in contents) {
            NSNumber* is_dir = nil;
            [item getResourceValue:&is_dir forKey:NSURLIsDirectoryKey error:nil];
            if (![is_dir boolValue]) {
                continue;
            }
            NSString* nested_model = [[item path]
                stringByAppendingPathComponent:[model_name stringByAppendingString:@".mlmodelc"]];
            if (rac_coreml_file_exists(nested_model)) {
                return [item path];
            }
        }
        return base_dir;
    } @catch (NSException* e) {
        RAC_LOG_ERROR(kLogCat, "find_resource_dir raised %s under %s: %s",
                      e.name ? [e.name UTF8String] : "NSException",
                      base_dir ? [base_dir UTF8String] : "<nil>",
                      e.reason ? [e.reason UTF8String] : "no reason");
        return base_dir;
    }
}

MLModel* rac_coreml_load_model_in_dir(NSString* dir, NSString* name, bool required,
                                      const char* log_category) {
    NSString* path =
        [dir stringByAppendingPathComponent:[name stringByAppendingString:@".mlmodelc"]];
    NSURL* url = [NSURL fileURLWithPath:path];
    const char* category = log_category ? log_category : kLogCat;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (required) {
            RAC_LOG_ERROR(category, "Required MLModel missing: %s", [path UTF8String]);
        }
        return nil;
    }

    // +[MLModel modelWithContentsOfURL:] can raise NSException on
    // malformed mlpackage payloads (corrupted coremldata.bin); the error:
    // out-param only catches user-recoverable failures. Return nil on any
    // catch so callers (diffusion_coreml_backend.mm etc.) treat it as a
    // missing optional model rather than crash the host process.
    @try {
        NSError* err = nil;
        MLModelConfiguration* cfg = rac_coreml_default_model_configuration();
        MLModel* model = [MLModel modelWithContentsOfURL:url configuration:cfg error:&err];
        if (!model) {
            RAC_LOG_ERROR(category, "MLModel load failed (%s): %s", [name UTF8String],
                          err ? [[err localizedDescription] UTF8String] : "unknown");
            return nil;
        }
        // +modelWithContentsOfURL: returns an autoreleased instance — promote it
        // to a retained reference so callers that store the pointer into
        // long-lived engine state (e.g. diffusion_coreml_backend.mm) don't end
        // up with a dangling reference after the enclosing @autoreleasepool
        // drains. NS_RETURNS_RETAINED documents the matching -release contract.
        return [model retain];
    } @catch (NSException* e) {
        RAC_LOG_ERROR(category, "MLModel load raised %s on %s: %s",
                      e.name ? [e.name UTF8String] : "NSException", [name UTF8String],
                      e.reason ? [e.reason UTF8String] : "no reason");
        return nil;
    }
}

extern "C" rac_result_t rac_coreml_runtime_require_available(void) {
    return rac_runtime_get_by_id(RAC_RUNTIME_COREML) != nullptr ? RAC_SUCCESS
                                                                : RAC_ERROR_BACKEND_UNAVAILABLE;
}

extern "C" RAC_API const rac_runtime_vtable_t* rac_runtime_entry_coreml(void) {
    return &k_coreml_vtable;
}

RAC_STATIC_RUNTIME_REGISTER(coreml);

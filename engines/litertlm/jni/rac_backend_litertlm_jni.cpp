/**
 * LiteRT-LM backend JNI bridge.
 *
 * Linked by: bindings/kotlin/modules/runanywhere-core-litertlm
 * Package: com.runanywhere.sdk.llm.litertlm   Class: LiteRTLMBridge
 */

#include "rac_litertlm.h"

#include <jni.h>

#include "../../common/rac_engine_jni_bridge.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_primitive.h"

RAC_DEFINE_ENGINE_JNI_LOG_TAG("JNI.LiteRTLM");

#ifndef RAC_LITERTLM_VERSION
#define RAC_LITERTLM_VERSION "unknown"
#endif

extern "C" {

RAC_DEFINE_ENGINE_JNI_BRIDGE(com_runanywhere_sdk_llm_litertlm_LiteRTLMBridge,
                             rac_backend_litertlm_register, rac_backend_litertlm_unregister,
                             "LiteRT-LM", "", RAC_ENGINE_JNI_NO_AFTER_REGISTER,
                             RAC_PRIMITIVE_GENERATE_TEXT, "litertlm", RAC_LITERTLM_VERSION)

}  // extern "C"

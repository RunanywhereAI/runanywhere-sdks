#include <jni.h>
#include "HybridRunAnywhereRAG.hpp"
#include "runanywherergOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    // Call the generated initialization function to register hybrid objects
    return margelo::nitro::runanywhere::rag::initialize(vm);
}

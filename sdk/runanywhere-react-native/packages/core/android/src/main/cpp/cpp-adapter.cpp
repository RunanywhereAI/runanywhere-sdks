#include <jni.h>
#include "runanywherecoreOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return margelo::nitro::runanywhere::initialize(vm);
}

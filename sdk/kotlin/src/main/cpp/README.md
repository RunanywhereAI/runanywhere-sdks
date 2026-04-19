# JNI bridge for RunAnywhere v2 Kotlin adapter

Generated at build time from `core/abi/ra_pipeline.h`. Keeps the Kotlin
adapter thin — all real work happens in the C++ core.

Phase 2 deliverable: `jni_bridge.cpp` wired via a Gradle externalNativeBuild
CMake target. In this bootstrap PR the JNI layer is not yet linked.

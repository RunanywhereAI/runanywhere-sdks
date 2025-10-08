# CMakeLists.txt - DEPRECATED
# This Android app now uses the RunAnywhere KMP SDK for LLM functionality
# instead of implementing its own llama.cpp JNI bindings.
#
# The native build has been disabled in build.gradle.kts to avoid conflicts
# with the KMP SDK's native libraries.
#
# If you need to add custom native code in the future, ensure it does not
# conflict with the KMP SDK's native dependencies.

cmake_minimum_required(VERSION 3.22.1)
project("deprecated_native")

# This file is kept for reference but should not be built
# See build.gradle.kts where externalNativeBuild is commented out

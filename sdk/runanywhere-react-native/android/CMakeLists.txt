cmake_minimum_required(VERSION 3.13)
project(runanywhere-react-native)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_VERBOSE_MAKEFILE ON)

# Find React Native packages
find_package(ReactAndroid REQUIRED CONFIG)
find_package(fbjni REQUIRED CONFIG)

# C++ TurboModule source
add_library(
  runanywhere-react-native
  SHARED
  ../cpp/RunAnywhereModule.cpp
  src/main/cpp/react-native-runanywhere.cpp
)

# Include directories
target_include_directories(
  runanywhere-react-native
  PRIVATE
  ../cpp
  ../cpp/include
  ${REACT_NATIVE_DIR}/ReactCommon
  ${REACT_NATIVE_DIR}/ReactCommon/jsi
  ${REACT_NATIVE_DIR}/ReactCommon/callinvoker
  ${REACT_NATIVE_DIR}/ReactAndroid/src/main/jni/react/turbomodule
)

# Link against React Native and JSI
target_link_libraries(
  runanywhere-react-native
  ReactAndroid::jsi
  ReactAndroid::react_nativemodule_core
  ReactAndroid::turbomodulejsijni
  fbjni::fbjni
  android
  log
)

# Link against runanywhere-core C API (.so files)
find_library(runanywhere-bridge runanywhere_bridge
  PATHS ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI} NO_DEFAULT_PATH)
if(runanywhere-bridge)
  target_link_libraries(runanywhere-react-native ${runanywhere-bridge})
endif()

# Link against ONNX Runtime if available
find_library(onnxruntime-lib onnxruntime
  PATHS ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI} NO_DEFAULT_PATH)
if(onnxruntime-lib)
  target_link_libraries(runanywhere-react-native ${onnxruntime-lib})
endif()

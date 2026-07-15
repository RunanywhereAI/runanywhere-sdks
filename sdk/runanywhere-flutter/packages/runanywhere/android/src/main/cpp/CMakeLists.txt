cmake_minimum_required(VERSION 3.18.1)

project(runanywhere_flutter_helpers LANGUAGES CXX)

add_library(runanywhere_flutter_helpers SHARED NativePortHelpers.cpp)

set_target_properties(
    runanywhere_flutter_helpers
    PROPERTIES
        CXX_STANDARD 17
        CXX_STANDARD_REQUIRED ON
        CXX_EXTENSIONS OFF
)

target_compile_options(
    runanywhere_flutter_helpers
    PRIVATE
        -fvisibility=hidden
        -Wall
        -Wextra
)

if(ANDROID)
    target_link_options(
        runanywhere_flutter_helpers
        PRIVATE
            -Wl,-z,max-page-size=16384
            -Wl,-z,common-page-size=16384
            # Do not leak libc++ operator new/delete (or any static-runtime
            # symbol) out of this helper. Exporting them lets the dynamic linker
            # interpose this .so's allocator ahead of libc++_shared for other
            # libraries (e.g. llama.cpp gguf std::strings), which frees a buffer
            # on a different allocator view than it was allocated on and aborts
            # with "pointer tag truncated" on Android 15+. The version script
            # exports only the ra_flutter_* entry points + JNI_OnLoad.
            -Wl,--exclude-libs,ALL
            -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/runanywhere_flutter_helpers.map
    )
endif()

set(RAC_FLUTTER_JNILIBS_DIR "" CACHE PATH "Directory containing Flutter RACommons jniLibs")
set(RAC_COMMONS_LIB "${RAC_FLUTTER_JNILIBS_DIR}/${ANDROID_ABI}/librac_commons.so")

if(EXISTS "${RAC_COMMONS_LIB}")
    add_library(rac_commons SHARED IMPORTED GLOBAL)
    set_target_properties(
        rac_commons
        PROPERTIES IMPORTED_LOCATION "${RAC_COMMONS_LIB}"
    )
    target_link_libraries(runanywhere_flutter_helpers PRIVATE rac_commons)
else()
    message(FATAL_ERROR "librac_commons.so not found for ${ANDROID_ABI}: ${RAC_COMMONS_LIB}")
endif()

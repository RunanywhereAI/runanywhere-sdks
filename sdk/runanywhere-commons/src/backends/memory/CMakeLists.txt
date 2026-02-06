# Memory Backend - Vector Similarity Search via hnswlib + flat brute-force
message(STATUS "Configuring Memory backend...")

include(FetchContent)

# Fetch hnswlib (header-only library, zero dependencies)
FetchContent_Declare(
    hnswlib
    GIT_REPOSITORY https://github.com/nmslib/hnswlib.git
    GIT_TAG        v0.8.0
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(hnswlib)

# Backend sources
set(MEMORY_BACKEND_SOURCES
    memory_backend_flat.cpp
    memory_backend_hnswlib.cpp
    rac_memory_backend.cpp
    rac_backend_memory_register.cpp
)

add_library(rac_backend_memory STATIC ${MEMORY_BACKEND_SOURCES})

target_include_directories(rac_backend_memory PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${hnswlib_SOURCE_DIR}
)

target_link_libraries(rac_backend_memory PUBLIC rac_commons)
target_compile_features(rac_backend_memory PUBLIC cxx_std_17)

# Platform-specific configuration
if(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    # Use Accelerate framework for optimized BLAS operations if available
    target_link_libraries(rac_backend_memory PUBLIC "-framework Accelerate")
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Android")
    target_link_libraries(rac_backend_memory PRIVATE log)
    # 16KB page alignment for Android 15+ (Google Play requirement)
    target_link_options(rac_backend_memory PRIVATE -Wl,-z,max-page-size=16384)
endif()

message(STATUS "  Memory backend configured (hnswlib v0.8.0 + flat)")

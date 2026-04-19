cmake_minimum_required(VERSION 3.18)
project(flutter_rag_bridge)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Source directory (shared between iOS and Android)
set(SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../src)

# Bridge source files
add_library(flutter_rag_bridge SHARED
    ${SRC_DIR}/flutter_rag_bridge.cpp
)

# Include paths: bridge headers + nlohmann/json
target_include_directories(flutter_rag_bridge PRIVATE
    ${SRC_DIR}
    ${SRC_DIR}/third_party
)

# Link against prebuilt librac_commons.so
# The .so files are downloaded by build.gradle into build/jniLibs/ or src/main/jniLibs/
# We find them relative to the current ABI
set(JNILIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/build/jniLibs/${ANDROID_ABI})
set(JNILIB_DIR_LOCAL ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# Try build dir first (remote mode), then local dir
if(EXISTS "${JNILIB_DIR}/librac_commons.so")
    set(RAC_LIB_DIR ${JNILIB_DIR})
elseif(EXISTS "${JNILIB_DIR_LOCAL}/librac_commons.so")
    set(RAC_LIB_DIR ${JNILIB_DIR_LOCAL})
else()
    message(WARNING "librac_commons.so not found for ${ANDROID_ABI} - bridge will have unresolved symbols until runtime")
    set(RAC_LIB_DIR ${JNILIB_DIR})
endif()

# Import prebuilt rac_commons
add_library(rac_commons SHARED IMPORTED)
set_target_properties(rac_commons PROPERTIES
    IMPORTED_LOCATION "${RAC_LIB_DIR}/librac_commons.so"
)

target_link_libraries(flutter_rag_bridge
    rac_commons
    log
)

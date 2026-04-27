# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "runanywhere")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "runanywhere_plugin")

list(APPEND PLUGIN_SOURCES
  "runanywhere_plugin.cpp"
  "runanywhere_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/runanywhere/runanywhere_plugin_c_api.h"
  "runanywhere_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

get_filename_component(PACKAGE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
get_filename_component(REPO_ROOT_FROM_APP "${CMAKE_SOURCE_DIR}/../../../../" ABSOLUTE)

set(COMMONS_DLL_CANDIDATES
  "${REPO_ROOT_FROM_APP}/sdk/runanywhere-commons/dist/windows/x64/rac_commons.dll"
  "${PACKAGE_ROOT}/../../../runanywhere-commons/dist/windows/x64/rac_commons.dll"
)

set(COMMONS_DLL "")
foreach(candidate ${COMMONS_DLL_CANDIDATES})
  if(EXISTS "${candidate}")
    set(COMMONS_DLL "${candidate}")
    break()
  endif()
endforeach()

if(NOT EXISTS "${COMMONS_DLL}")
  message(FATAL_ERROR
    "Missing rac_commons.dll. Tried: ${COMMONS_DLL_CANDIDATES}. "
    "Build sdk/runanywhere-commons first with scripts/build-windows.bat.")
endif()

add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${COMMONS_DLL}"
  "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/rac_commons.dll"
)

set(runanywhere_bundled_libraries
  "${COMMONS_DLL}"
  PARENT_SCOPE
)

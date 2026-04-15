cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "flutter_secure_storage_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "flutter_secure_storage_windows_plugin")

add_library(${PLUGIN_NAME} SHARED
  "flutter_secure_storage_windows_plugin.cpp"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/include/flutter_secure_storage_windows")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
set(flutter_secure_storage_bundled_libraries
  ""
  PARENT_SCOPE
)
if(NOT DEFINED STORAGE_PREFIX)
  add_compile_definitions(SECURE_STORAGE_KEY_PREFIX="${BINARY_NAME}_VGhpcyBpcyB0aGUgcHJlZml4IGZv_")
else()
  add_compile_definitions(SECURE_STORAGE_KEY_PREFIX="${STORAGE_PREFIX}_VGhpcyBpcyB0aGUgcHJlZml4IGZv_")
endif()

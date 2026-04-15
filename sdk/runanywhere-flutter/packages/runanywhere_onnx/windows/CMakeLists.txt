cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "runanywhere_onnx")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "runanywhere_onnx_plugin")

list(APPEND PLUGIN_SOURCES
  "runanywhere_onnx_plugin.cpp"
  "runanywhere_onnx_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/runanywhere_onnx/runanywhere_onnx_plugin_c_api.h"
  "runanywhere_onnx_plugin_c_api.cpp"
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
set(ONNX_DIST_DIR_CANDIDATES
  "${REPO_ROOT_FROM_APP}/sdk/runanywhere-commons/dist/windows/x64"
  "${PACKAGE_ROOT}/../../../runanywhere-commons/dist/windows/x64"
)

set(ONNX_DIST_DIR "")
foreach(candidate ${ONNX_DIST_DIR_CANDIDATES})
  if(EXISTS "${candidate}")
    set(ONNX_DIST_DIR "${candidate}")
    break()
  endif()
endforeach()

if(EXISTS "${ONNX_DIST_DIR}")
  file(GLOB ONNX_DIST_DLLS "${ONNX_DIST_DIR}/*.dll")
  set(ONNX_RUNTIME_DLLS "")

  foreach(candidate ${ONNX_DIST_DLLS})
    get_filename_component(candidate_name "${candidate}" NAME)
    if(candidate_name STREQUAL "rac_backend_onnx.dll")
      list(APPEND ONNX_RUNTIME_DLLS "${candidate}")
    elseif(candidate_name MATCHES "^onnxruntime.*\\.dll$")
      list(APPEND ONNX_RUNTIME_DLLS "${candidate}")
    elseif(candidate_name MATCHES "^sherpa-onnx.*\\.dll$")
      list(APPEND ONNX_RUNTIME_DLLS "${candidate}")
    elseif(candidate_name STREQUAL "cargs.dll")
      list(APPEND ONNX_RUNTIME_DLLS "${candidate}")
    endif()
  endforeach()

  if(ONNX_RUNTIME_DLLS)
    foreach(runtime_dll ${ONNX_RUNTIME_DLLS})
      add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${runtime_dll}"
        "$<TARGET_FILE_DIR:${PLUGIN_NAME}>"
      )
    endforeach()

    set(runanywhere_onnx_bundled_libraries
      ${ONNX_RUNTIME_DLLS}
      PARENT_SCOPE
    )
  else()
    message(WARNING
      "No ONNX runtime DLLs found in ${ONNX_DIST_DIR}. "
      "Windows builds will continue without ONNX support.")
    set(runanywhere_onnx_bundled_libraries
      ""
      PARENT_SCOPE
    )
  endif()
else()
  message(WARNING
    "ONNX dist directory not found. Tried: ${ONNX_DIST_DIR_CANDIDATES}. "
    "Windows builds will continue without ONNX support.")
  set(runanywhere_onnx_bundled_libraries
    ""
    PARENT_SCOPE
  )
endif()

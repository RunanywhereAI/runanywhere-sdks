# MetalRT Backend — Apple-only (iOS/macOS)
#
# The MetalRT engine (libmetalrt_engine.a + metalrt_c_api.h) is a private,
# closed-source dependency. This CMakeLists supports two modes:
#
#   1) Engine NOT available (default in the public repo):
#      - RAC_METALRT_ENGINE_AVAILABLE is OFF.
#      - The public stub header and stub source under stubs/ are compiled in.
#      - Every metalrt_* symbol resolves to a no-op returning a sentinel.
#      - The public repo links cleanly. At runtime, the wrappers + vtable
#        registration short-circuit to RAC_ERROR_BACKEND_UNAVAILABLE before
#        invoking these stubs, so loadModel(..., framework: .metalrt) returns
#        a clean error instead of a crash.
#
#   2) Engine IS available (internal / authorized builds):
#      - RAC_METALRT_ENGINE_AVAILABLE=ON.
#      - METALRT_ROOT must point at the private MetalRT project.
#      - The real metalrt_c_api.h from METALRT_ROOT/src is used; stubs are
#        skipped. libmetalrt_engine.a is linked via find_library (REQUIRED).
#      - Configure fails hard if the engine is claimed-available but missing,
#        consistent with how llamacpp/onnx handle missing deps.

option(RAC_METALRT_ENGINE_AVAILABLE
    "Link the private MetalRT engine (libmetalrt_engine.a). OFF = compile stubs only."
    OFF)

set(METALRT_WRAPPER_SOURCES
    rac_llm_metalrt.cpp
    rac_stt_metalrt.cpp
    rac_tts_metalrt.cpp
    rac_vlm_metalrt.cpp
    rac_backend_metalrt_register.cpp
)

# Folded into rac_commons as an OBJECT library — no separate artifact to ship.
add_library(rac_backend_metalrt OBJECT ${METALRT_WRAPPER_SOURCES})

target_include_directories(rac_backend_metalrt PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_definitions(rac_backend_metalrt PRIVATE RAC_METALRT_BUILDING)

if(RAC_METALRT_ENGINE_AVAILABLE)
    # ------------------------------------------------------------------
    # Real engine path — MetalRT project must be present and built.
    # ------------------------------------------------------------------
    if(NOT DEFINED METALRT_ROOT)
        # Default: assume MetalRT is sibling to runanywhere-sdks
        set(METALRT_ROOT "${CMAKE_SOURCE_DIR}/../../../MetalRT" CACHE PATH "Path to MetalRT project root")
    endif()

    set(METALRT_INCLUDE_DIR "${METALRT_ROOT}/src" CACHE PATH "Path to metalrt_c_api.h")

    if(DEFINED METALRT_LIB_DIR)
        set(_metalrt_lib_dir "${METALRT_LIB_DIR}")
    else()
        set(_metalrt_lib_dir "${METALRT_ROOT}/build")
    endif()

    # NO_CMAKE_FIND_ROOT_PATH: the engine is built locally, not inside the iOS sysroot.
    find_library(METALRT_ENGINE_LIB
        NAMES metalrt_engine
        PATHS ${_metalrt_lib_dir}
        NO_DEFAULT_PATH
        NO_CMAKE_FIND_ROOT_PATH
        REQUIRED
    )

    message(STATUS "MetalRT: engine AVAILABLE, linking ${METALRT_ENGINE_LIB}")
    target_include_directories(rac_backend_metalrt PRIVATE ${METALRT_INCLUDE_DIR})
    target_compile_definitions(rac_backend_metalrt PRIVATE RAC_METALRT_ENGINE_AVAILABLE=1)

    # The parent CMakeLists folds this target's objects into rac_commons; the
    # engine .a needs to be linked onto rac_commons from the parent scope so
    # that the OBJECT target's undefined symbols resolve in the final archive.
    set(RAC_METALRT_ENGINE_LIB ${METALRT_ENGINE_LIB} PARENT_SCOPE)
else()
    # ------------------------------------------------------------------
    # Stub path — public-repo default. Compile the stub .c file so every
    # metalrt_* symbol resolves to a no-op. No external dependency.
    # ------------------------------------------------------------------
    message(STATUS "MetalRT: engine not available — compiling stubs")
    target_sources(rac_backend_metalrt PRIVATE stubs/metalrt_c_api_stub.c)
    target_include_directories(rac_backend_metalrt PRIVATE stubs)
    target_compile_definitions(rac_backend_metalrt PRIVATE RAC_METALRT_ENGINE_AVAILABLE=0)
endif()

# Apple frameworks are always needed on this target (the wrappers reference
# Metal-framework types in some paths even without the engine).
target_link_libraries(rac_backend_metalrt PRIVATE
    "-framework Metal"
    "-framework Foundation"
    "-framework Accelerate"
)

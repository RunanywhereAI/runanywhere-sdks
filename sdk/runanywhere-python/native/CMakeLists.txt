# runanywhere-python — native layer.
#
# Builds the pybind11 extension module `_core` (import name runanywhere._core),
# gated by RAC_BUILD_PYTHON_MODULE (OFF by default so normal builds are unaffected).
# Built as a ROOT target so CMake's dependency graph supplies the full transitive
# static-lib set (rac_commons + rac_backend_* pull llama/ggml/onnx/sherpa/protobuf/
# libarchive/zlib/... transitively — the set the electron M0 harness first proved
# links cleanly on MSVC).
if(NOT RAC_BUILD_PYTHON_MODULE)
    return()
endif()

# On MSVC, libarchive/find_package leak the bundled zlib/bz2 statics into the link
# line as bare names, resolved via a directory-scoped link_directories in the
# commons subdir that does NOT reach this sibling subdir. Re-add it for our target.
set(_ra_bundled_dir "${CMAKE_BINARY_DIR}/_bundled_libs")

# Python: the interpreter builds/loads the module, Development.Module supplies the
# headers + link stubs for a Python extension (no libpython on the link line).
find_package(Python COMPONENTS Interpreter Development.Module REQUIRED)

# Prefer the pip-installed pybind11 (3.x) discovered via its CMake config package;
# fall back to fetching v3.0.0 only when it is not already available.
find_package(pybind11 CONFIG QUIET)
if(NOT pybind11_FOUND)
    include(FetchContent)
    FetchContent_Declare(pybind11
        GIT_REPOSITORY https://github.com/pybind/pybind11.git
        GIT_TAG        v3.0.0)
    FetchContent_MakeAvailable(pybind11)
    message(STATUS "runanywhere-python: pybind11 not found — fetched v3.0.0")
else()
    message(STATUS "runanywhere-python: using found pybind11 ${pybind11_VERSION}")
endif()

# Select the platform adapter for host HTTP/keystore/filesystem services.
if(WIN32)
    set(_ra_adapter win32_platform_adapter.cpp)
else()
    set(_ra_adapter posix_platform_adapter.cpp)
endif()

pybind11_add_module(runanywhere_core MODULE module.cpp ${_ra_adapter})
# Import name is runanywhere._core; the file must be _core, not runanywhere_core.
set_target_properties(runanywhere_core PROPERTIES OUTPUT_NAME "_core")

target_include_directories(runanywhere_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include)
target_compile_features(runanywhere_core PRIVATE cxx_std_20)
target_link_libraries(runanywhere_core PRIVATE rac_commons)

# Link whichever engine backends this build enabled, and tell module.cpp which are present
# via RAC_HAVE_BACKEND_<X>. The wrapper registers only the linked backends and the C plugin
# registry routes by priority — so adding a backend (QHexRT on Windows-on-Snapdragon, MLX,
# CoreML, cloud, ...) is: enable its upstream RAC_BACKEND_* flag so its rac_backend_<x> target
# builds, and it self-links + self-registers here with no wrapper source changes. The default
# CPU build (RAC_BUILD_BACKENDS=ON) provides llamacpp + onnx + sherpa.
set(_ra_backends llamacpp onnx sherpa qhexrt mlx coreml cloud)
set(_ra_linked_backends "")
foreach(_ra_b IN LISTS _ra_backends)
    if(TARGET rac_backend_${_ra_b})
        target_link_libraries(runanywhere_core PRIVATE rac_backend_${_ra_b})
        string(TOUPPER "${_ra_b}" _ra_bU)
        target_compile_definitions(runanywhere_core PRIVATE RAC_HAVE_BACKEND_${_ra_bU})
        list(APPEND _ra_linked_backends ${_ra_b})
    endif()
endforeach()
message(STATUS "runanywhere-python: engine backends -> ${_ra_linked_backends}")

if(MSVC)
    target_link_directories(runanywhere_core PRIVATE "${_ra_bundled_dir}")
    target_link_libraries(runanywhere_core PRIVATE Crypt32)
    # Keep the builder's absolute PDB/build path out of the shipped .pyd (release hygiene —
    # the public-package validator rejects embedded host paths like C:\Users\...). %_PDB%
    # embeds only the PDB basename; /Brepro drops the non-deterministic build-path record.
    target_link_options(runanywhere_core PRIVATE /PDBALTPATH:%_PDB% /Brepro)
    # zlibstatic / bz2_bundled are consumed by BARE NAME (commons cache-forces
    # ZLIB_LIBRARIES="zlibstatic"; libarchive leaks bz2_bundled likewise). They are
    # EXCLUDE_FROM_ALL FetchContent targets and are NOT visible as targets in this scope
    # (if(TARGET) is false here), so nothing links/depends them and a lone
    # `--target runanywhere_core` leaves _bundled_libs empty (LNK1181 zlibstatic.lib).
    # Build them via a nested `cmake --build --target` in a PRE_LINK step so they land in
    # _bundled_libs (their ARCHIVE_OUTPUT_DIRECTORY, set by commons) before we link.
    # Generator-specific: the multi-config VS generator only resolves such a target from
    # ITS OWN subdir build tree; single-config Ninja/Makefiles resolve any target from the
    # root build dir. (The subdir paths are stable for this project.)
    if(CMAKE_GENERATOR MATCHES "Visual Studio")
        add_custom_command(TARGET runanywhere_core PRE_LINK
            COMMAND "${CMAKE_COMMAND}" --build "${CMAKE_BINARY_DIR}/_deps/zlib_src-build"
                    --config $<CONFIG> --target zlibstatic
            COMMAND "${CMAKE_COMMAND}" --build "${CMAKE_BINARY_DIR}/sdk/runanywhere-commons"
                    --config $<CONFIG> --target bz2_bundled
            VERBATIM
            COMMENT "runanywhere-python: building bundled zlib/bz2 statics -> _bundled_libs")
    else()
        add_custom_command(TARGET runanywhere_core PRE_LINK
            COMMAND "${CMAKE_COMMAND}" --build "${CMAKE_BINARY_DIR}" --target zlibstatic bz2_bundled
            VERBATIM
            COMMENT "runanywhere-python: building bundled zlib/bz2 statics -> _bundled_libs")
    endif()
    target_compile_definitions(runanywhere_core PRIVATE
        _CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
    target_compile_options(runanywhere_core PRIVATE /EHsc /Zc:__cplusplus /utf-8 /bigobj)
elseif(APPLE)
    # The module ships next to the bundled dylibs inside runanywhere/_native.
    set_target_properties(runanywhere_core PROPERTIES INSTALL_RPATH "@loader_path")
else()
    # Linux: resolve co-located bundled .so siblings relative to the module.
    set_target_properties(runanywhere_core PROPERTIES INSTALL_RPATH "$ORIGIN")
endif()

# Install ONLY the module, into the install-tree root (scikit-build maps that to the
# wheel's `wheel.install-dir` = runanywhere/_native). A dedicated component lets the wheel
# build install just this (pyproject `install.components`), so the transitive header / .lib
# / cmake / docs install rules from commons+llama+zlib do NOT pollute the wheel. The
# sidecar runtime DLLs are vendored by delvewheel/auditwheel/delocate at repair time.
install(TARGETS runanywhere_core
    LIBRARY DESTINATION . COMPONENT python_module
    RUNTIME DESTINATION . COMPONENT python_module)

message(STATUS "runanywhere-python: pybind11 module 'runanywhere_core' (_core) enabled")

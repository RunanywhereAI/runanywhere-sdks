# =============================================================================
# runtimes/cpu — built-in CPU runtime plugin.
#
# Task T4.1 — see sdk/runanywhere-commons/docs/RUNTIME_VTABLE_DESIGN.md.
#
# The CPU runtime is always available on every host. We build it as an
# OBJECT library and fold its objects into rac_commons (mirrors the
# metalrt approach), so there is no separate librac_runtime_cpu.* to ship.
# Consumers who want to force a static link for iOS / WASM static-linking
# reference `rac_runtime_static_marker_cpu` — emitted by
# RAC_STATIC_RUNTIME_REGISTER(cpu) inside rac_runtime_cpu.cpp.
# =============================================================================

add_library(rac_runtime_cpu OBJECT
    rac_runtime_cpu.cpp
)

set_target_properties(rac_runtime_cpu PROPERTIES
    CXX_STANDARD          20
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(rac_runtime_cpu PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Tooling metadata — mirrors what rac_add_engine_plugin records for engines.
set_property(GLOBAL APPEND PROPERTY RAC_REGISTERED_RUNTIMES cpu)
set_property(GLOBAL APPEND PROPERTY RAC_RUNTIME_cpu_DEVICE_CLASS CPU)

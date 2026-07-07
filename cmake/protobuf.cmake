# =============================================================================
# cmake/protobuf.cmake — Protobuf + absl detection
#
# Wraps `find_package(Protobuf)` and probes absl so proto-consuming
# C++ targets — chiefly rac_commons, which compiles the committed *.pb.cc under
# sdk/runanywhere-commons/src/generated/proto/ — get consistent runtime + absl
# link deps without each running its own skip-if-missing block.
#
# Outputs:
#   RAC_HAVE_PROTOBUF — TRUE/FALSE; consumers branch on this.
#   RAC_ABSL_LIBS     — list of usable absl::* imported targets to link.
#   When TRUE: imported target `protobuf::libprotobuf` is available.
#
# Usage:
#   include(protobuf)
#   if(RAC_HAVE_PROTOBUF)
#       target_link_libraries(<tgt> PUBLIC protobuf::libprotobuf ${RAC_ABSL_LIBS})
#   endif()
# =============================================================================

include_guard(GLOBAL)

# Protobuf must exactly match the checked-in generated C++ sources.
#
# Checked-in generated headers under sdk/runanywhere-commons/src/generated/proto
# include an exact `PROTOBUF_VERSION` preprocessor guard. Newer patch releases
# can satisfy a loose `find_package(Protobuf 5.0)` probe but still fail during
# compilation. Keep this early, optional probe exact so it cannot pre-register
# incompatible `protobuf::` imported targets before rac_commons vendors the
# pinned runtime.
include(LoadVersions OPTIONAL)
set(RAC_PROTOBUF_EXACT_VERSION "${RAC_PROTOBUF_VERSION}" CACHE STRING
    "Exact Protobuf source version matching checked-in generated C++ sources.")

find_package(Protobuf ${RAC_PROTOBUF_EXACT_VERSION} EXACT CONFIG QUIET)

# SHARED-build consumers of proto-generated .pb.cc.o files
# (rac_voice_event_abi.cpp, pipeline.pb.cc, etc.) need absl symbols at
# link time (absl::log_internal::Check*, absl::hash_internal::*).
# Modern Homebrew protobuf 22+ ships with absl as a separate package;
# module-mode FindProtobuf.cmake doesn't propagate the absl deps. Find
# absl independently and expose only the components whose imported targets
# actually exist — older absl (Ubuntu 22.04 ships 20210324) is missing
# absl::log, so linking it unconditionally produces "Target ... links to
# absl::log but the target was not found".
find_package(absl QUIET CONFIG)
set(RAC_ABSL_LIBS "")
if(absl_FOUND)
    foreach(_rac_absl_component
            absl::log
            absl::log_internal_check_op
            absl::hash
            absl::strings
            absl::status)
        if(TARGET ${_rac_absl_component})
            list(APPEND RAC_ABSL_LIBS ${_rac_absl_component})
        endif()
    endforeach()
    message(STATUS "absl: found via CONFIG (${absl_VERSION}); usable targets: ${RAC_ABSL_LIBS}")
endif()

if(Protobuf_FOUND)
    set(RAC_HAVE_PROTOBUF TRUE)
    message(STATUS "Protobuf: found ${Protobuf_VERSION} (${Protobuf_LIBRARIES})")
else()
    set(RAC_HAVE_PROTOBUF FALSE)
    message(STATUS "Protobuf: no exact ${RAC_PROTOBUF_EXACT_VERSION} CONFIG package found — "
                   "rac_commons may vendor the pinned runtime if protobuf is enabled.")
endif()

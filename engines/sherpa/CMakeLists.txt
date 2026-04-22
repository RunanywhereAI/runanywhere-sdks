# =============================================================================
# engines/sherpa — Sherpa-ONNX STT (peeled out of the legacy ONNX backend)
#
# GAP 06 Phase 10 — see v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md.
#
# Sherpa-ONNX (NeMo CTC / Parakeet) was historically conditionally compiled
# into engines/onnx/ via RAC_USE_SHERPA_ONNX. Spec calls for splitting it
# into a standalone plugin so:
#   - hosts that only want vanilla ONNX Runtime don't pay the sherpa link cost,
#   - hosts that DO want sherpa can dlopen this plugin separately.
#
# Today this is a SCAFFOLD: ships the rac_add_engine_plugin() registration
# with a NULL ops table so the registry knows the engine name + runtimes +
# formats it would serve. The actual sherpa wrapper sources will land in a
# follow-up commit when the ONNX backend is sliced (`engines/onnx` keeps
# its current sherpa block until the slice is verified).
# =============================================================================

option(RAC_BACKEND_SHERPA "Build the standalone Sherpa-ONNX STT engine plugin" OFF)

if(RAC_BACKEND_SHERPA)
    rac_add_engine_plugin(sherpa
        SOURCES
            rac_plugin_entry_sherpa.cpp
        RUNTIMES CPU
        FORMATS  ONNX
    )
endif()

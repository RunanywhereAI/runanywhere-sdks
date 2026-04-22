# =============================================================================
# engines/diffusion-coreml — Apple CoreML Stable Diffusion engine plugin
#
# GAP 06 Phase 10 scaffold. Currently the CoreML diffusion path lives inside
# `sdk/runanywhere-commons/src/features/diffusion/` (Apple-only). The spec
# calls for peeling it into a dedicated plugin so the diffusion primitive
# routes through the unified registry like every other primitive.
#
# Today's wiring keeps the production diffusion code where it is (still
# linked into rac_commons on Apple) and registers a plugin scaffold that
# claims the diffusion primitive + COREML/MLPACKAGE formats so the router
# can score it. The actual ops slot stays NULL until the existing diffusion
# code is wrapped behind the unified ops table.
# =============================================================================

option(RAC_BACKEND_DIFFUSION_COREML "Build the standalone CoreML diffusion plugin" OFF)

if(APPLE AND RAC_BACKEND_DIFFUSION_COREML)
    rac_add_engine_plugin(diffusion-coreml
        SOURCES rac_plugin_entry_diffusion.cpp
        RUNTIMES COREML ANE
        FORMATS  COREML MLPACKAGE
    )
endif()

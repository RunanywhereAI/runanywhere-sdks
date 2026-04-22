# =============================================================================
# engines/genie — Qualcomm Genie LLM (Hexagon NPU) plugin scaffold
#
# GAP 06 Phase 10. RAC_RUNTIME_QNN was reserved in GAP 04 (rac_primitive.h)
# but no in-tree plugin claimed it. This scaffold gives the router a real
# target to score, and lets HardwareProfile::has_qnn=true on Snapdragon
# devices participate in routing decisions.
# =============================================================================

option(RAC_BACKEND_GENIE "Build the standalone Qualcomm Genie LLM engine plugin" OFF)

if(RAC_BACKEND_GENIE)
    rac_add_engine_plugin(genie
        SOURCES rac_plugin_entry_genie.cpp
        RUNTIMES QNN
        FORMATS  QNN_CONTEXT
    )
endif()

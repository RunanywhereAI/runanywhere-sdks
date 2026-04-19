ra_add_engine_plugin(llamacpp_engine
    SOURCES
        llamacpp_plugin.cpp
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_llamacpp
)

# In a future PR this section will do:
#   find_package(llama CONFIG REQUIRED)
#   target_link_libraries(llamacpp_engine PRIVATE llama)
# For now the plugin ships stub implementations of llm_generate/embed_text
# that return RA_ERR_RUNTIME_UNAVAILABLE with a clear message.

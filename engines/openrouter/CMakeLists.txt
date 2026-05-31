option(RAC_BACKEND_OPENROUTER "Build OpenRouter cloud LLM backend" ON)
if(NOT RAC_BACKEND_OPENROUTER)
    return()
endif()

message(STATUS "Configuring OpenRouter backend...")

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

add_library(rac_backend_openrouter STATIC rac_llm_openrouter.cpp)

target_include_directories(rac_backend_openrouter
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
)

target_link_libraries(rac_backend_openrouter
    PRIVATE
        rac_commons
        nlohmann_json::nlohmann_json
)

target_compile_features(rac_backend_openrouter PRIVATE cxx_std_17)
set_target_properties(rac_backend_openrouter PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(TARGET runanywhere_commons_jni)
    # JNI thunks live here, not in the commons JNI dir, because the commons
    # JNI CMakeLists is processed before engines/ and so cannot reliably see
    # RAC_BACKEND_OPENROUTER. Attaching the source here guarantees they end
    # up in librunanywhere_jni.so whenever this engine is built.
    target_sources(runanywhere_commons_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/jni/rac_openrouter_jni.cpp
    )
    target_link_libraries(runanywhere_commons_jni rac_backend_openrouter)
    target_include_directories(runanywhere_commons_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
endif()

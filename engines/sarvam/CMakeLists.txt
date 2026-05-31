option(RAC_BACKEND_SARVAM "Build Sarvam cloud STT backend" ON)
if(NOT RAC_BACKEND_SARVAM)
    return()
endif()

message(STATUS "Configuring Sarvam backend...")

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

add_library(rac_backend_sarvam STATIC rac_stt_sarvam.cpp)

target_include_directories(rac_backend_sarvam
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
)

target_link_libraries(rac_backend_sarvam
    PRIVATE
        rac_commons
        nlohmann_json::nlohmann_json
)

target_compile_features(rac_backend_sarvam PRIVATE cxx_std_17)
set_target_properties(rac_backend_sarvam PROPERTIES POSITION_INDEPENDENT_CODE ON)

if(TARGET runanywhere_commons_jni)
    # Same pattern as engines/openrouter: attach JNI thunks here because the
    # commons JNI CMakeLists is processed before engines/ and cannot see
    # RAC_BACKEND_SARVAM. Guarantees racSttSarvam* symbols end up in
    # librunanywhere_jni.so whenever this engine is built.
    target_sources(runanywhere_commons_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/jni/rac_stt_sarvam_jni.cpp
    )
    target_link_libraries(runanywhere_commons_jni rac_backend_sarvam)
    target_include_directories(runanywhere_commons_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
    )
endif()
cmake_minimum_required(VERSION 3.22)

# =============================================================================
# Integration Test Suite for runanywhere-commons
# =============================================================================

# --- test_core: Always built (no backend dependency) ---
add_executable(test_core test_core.cpp)
target_include_directories(test_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_core PRIVATE rac_commons)
target_compile_features(test_core PRIVATE cxx_std_17)
add_test(NAME core_tests COMMAND test_core --run-all)

# --- ONNX backend tests (VAD, STT, TTS, WakeWord) ---
if(RAC_BACKEND_ONNX AND TARGET rac_backend_onnx)
    # VAD test
    add_executable(test_vad test_vad.cpp)
    target_include_directories(test_vad PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_vad PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_vad PRIVATE cxx_std_17)
    add_test(NAME vad_tests COMMAND test_vad --run-all)

    # STT test
    add_executable(test_stt test_stt.cpp)
    target_include_directories(test_stt PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_stt PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_stt PRIVATE cxx_std_17)
    add_test(NAME stt_tests COMMAND test_stt --run-all)

    # TTS test
    add_executable(test_tts test_tts.cpp)
    target_include_directories(test_tts PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_tts PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_tts PRIVATE cxx_std_17)
    add_test(NAME tts_tests COMMAND test_tts --run-all)

    # WakeWord test
    add_executable(test_wakeword test_wakeword.cpp)
    target_include_directories(test_wakeword PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_wakeword PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_wakeword PRIVATE cxx_std_17)
    add_test(NAME wakeword_tests COMMAND test_wakeword --run-all)
endif()

# --- LLM test: Requires LlamaCPP backend ---
if(RAC_BACKEND_LLAMACPP AND TARGET rac_backend_llamacpp)
    add_executable(test_llm test_llm.cpp)
    target_include_directories(test_llm PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_llm PRIVATE rac_commons rac_backend_llamacpp)
    target_compile_features(test_llm PRIVATE cxx_std_17)
    add_test(NAME llm_tests COMMAND test_llm --run-all)
endif()

# --- Voice Agent test: Requires ONNX + LlamaCPP ---
if(RAC_BACKEND_ONNX AND RAC_BACKEND_LLAMACPP
   AND TARGET rac_backend_onnx AND TARGET rac_backend_llamacpp)
    add_executable(test_voice_agent test_voice_agent.cpp)
    target_include_directories(test_voice_agent PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_voice_agent PRIVATE
        rac_commons rac_backend_onnx rac_backend_llamacpp)
    target_compile_features(test_voice_agent PRIVATE cxx_std_17)
    add_test(NAME voice_agent_tests COMMAND test_voice_agent --run-all)
endif()

# --- macOS RPATH for ONNX Runtime dylib ---
if(APPLE)
    set(ONNX_MACOS_LIB_DIR "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-macos/lib")
    foreach(test_target test_vad test_stt test_tts test_wakeword test_voice_agent)
        if(TARGET ${test_target})
            set_target_properties(${test_target} PROPERTIES
                BUILD_RPATH "${ONNX_MACOS_LIB_DIR}"
                INSTALL_RPATH "${ONNX_MACOS_LIB_DIR}"
            )
        endif()
    endforeach()
endif()

# --- Linux RPATH for Sherpa-ONNX shared libs ---
if(UNIX AND NOT APPLE)
    set(SHERPA_LINUX_LIB_DIR "${CMAKE_SOURCE_DIR}/third_party/sherpa-onnx-linux/lib")
    foreach(test_target test_vad test_stt test_tts test_wakeword test_voice_agent)
        if(TARGET ${test_target})
            set_target_properties(${test_target} PROPERTIES
                BUILD_RPATH "$ORIGIN;${SHERPA_LINUX_LIB_DIR}"
                INSTALL_RPATH "$ORIGIN;${SHERPA_LINUX_LIB_DIR}"
            )
        endif()
    endforeach()
endif()

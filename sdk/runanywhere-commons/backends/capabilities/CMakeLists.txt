# RunAnywhere Capabilities
# Header-only capability interfaces

set(CAPABILITY_HEADERS
    capability.h
    backend.h
    text_generation.h
    embeddings.h
    stt.h
    tts.h
    vad.h
    diarization.h
)

# Create interface library for capabilities (header-only)
add_library(runanywhere_capabilities INTERFACE)
target_include_directories(runanywhere_capabilities INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/../include              # Public headers
    ${CMAKE_SOURCE_DIR}/../include/backends     # Backend public headers
    ${RAC_INCLUDE_DIR}                          # Commons headers (rac/core/*)
)

# Require nlohmann/json
find_package(nlohmann_json QUIET)
if(NOT nlohmann_json_FOUND)
    include(FetchContent)
    # Load centralized versions if not already loaded
    include(LoadVersions)
    FetchContent_Declare(
        json
        URL https://github.com/nlohmann/json/releases/download/v${NLOHMANN_JSON_VERSION}/json.tar.xz
    )
    FetchContent_MakeAvailable(json)
endif()

target_link_libraries(runanywhere_capabilities INTERFACE nlohmann_json::nlohmann_json)

# Install headers
install(FILES ${CAPABILITY_HEADERS}
    DESTINATION include/runanywhere/capabilities
)

# Sanitizer configuration.
#
# ASan + UBSan ship together in Debug builds (compatible, overlap is fine).
# TSan is mutually exclusive with ASan — enable via RA_ENABLE_TSAN=ON in its
# own CI job.

add_library(ra_sanitizers INTERFACE)
install(TARGETS ra_sanitizers EXPORT RunAnywhereTargets)
add_library(RunAnywhere::sanitizers ALIAS ra_sanitizers)

if(MSVC)
    # MSVC ships /fsanitize=address only; UBSan and TSan unsupported.
    if(RA_ENABLE_SANITIZERS AND CMAKE_BUILD_TYPE STREQUAL "Debug")
        target_compile_options(ra_sanitizers INTERFACE /fsanitize=address)
    endif()
    return()
endif()

if(RA_ENABLE_TSAN AND RA_ENABLE_SANITIZERS)
    message(FATAL_ERROR
        "RA_ENABLE_TSAN and RA_ENABLE_SANITIZERS (ASan+UBSan) are mutually exclusive. "
        "Run ASan+UBSan and TSan in separate CI jobs.")
endif()

if(RA_ENABLE_SANITIZERS AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(ra_sanitizers INTERFACE
        -fsanitize=address,undefined
        -fno-omit-frame-pointer
        -fno-sanitize-recover=all   # Convert UBSan warnings into hard failures.
    )
    target_link_options(ra_sanitizers INTERFACE
        -fsanitize=address,undefined
    )
endif()

if(RA_ENABLE_TSAN AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(ra_sanitizers INTERFACE
        -fsanitize=thread
        -fno-omit-frame-pointer
    )
    target_link_options(ra_sanitizers INTERFACE
        -fsanitize=thread
    )
endif()

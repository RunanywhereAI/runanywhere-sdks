add_executable(ra_validate validator.cpp)
target_link_libraries(ra_validate
    PRIVATE
        RunAnywhere::platform_flags
        RunAnywhere::sanitizers
)
# Link ra_idl when protobuf is available — the validator's next
# iteration parses PipelineSpec directly. When protobuf is absent
# (no vcpkg, no system protobuf) ra_validate falls back to the
# "length-only" diagnostic mode.
if(TARGET RunAnywhere::idl)
    target_link_libraries(ra_validate PRIVATE RunAnywhere::idl)
    target_compile_definitions(ra_validate PRIVATE RA_VALIDATE_HAS_PROTO=1)
endif()
install(TARGETS ra_validate RUNTIME DESTINATION bin)

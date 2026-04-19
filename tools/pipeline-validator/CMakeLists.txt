add_executable(ra_validate validator.cpp)
target_link_libraries(ra_validate
    PRIVATE
        RunAnywhere::platform_flags
        RunAnywhere::sanitizers
)
install(TARGETS ra_validate RUNTIME DESTINATION bin)

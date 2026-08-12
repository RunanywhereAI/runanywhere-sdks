# Prefetch a FetchContent URL with curl --http1.1, then point FetchContent at
# the local archive. GitHub release downloads over HTTP/2 regularly get
# REFUSED_STREAM / 503 on CI (Windows schannel especially); FetchContent's own
# 5 retries still use HTTP/2 and fail the configure.
#
# Extra arguments are forwarded to FetchContent_Declare (URL_HASH, etc.).
include_guard(GLOBAL)
include(FetchContent)

macro(rac_fetchcontent_archive name url)
    string(REGEX MATCH "[^/]+$" _rac_fc_fname "${url}")
    set(_rac_fc_dest "${CMAKE_BINARY_DIR}/_deps/${name}-archive/${_rac_fc_fname}")
    get_filename_component(_rac_fc_dir "${_rac_fc_dest}" DIRECTORY)
    file(MAKE_DIRECTORY "${_rac_fc_dir}")
    set(_rac_fc_local FALSE)
    if(EXISTS "${_rac_fc_dest}")
        set(_rac_fc_local TRUE)
    else()
        find_program(_rac_fc_curl NAMES curl curl.exe)
        if(_rac_fc_curl)
            foreach(_rac_fc_attempt RANGE 1 8)
                message(STATUS "Downloading ${name} (attempt ${_rac_fc_attempt}/8): ${url}")
                execute_process(
                    COMMAND "${_rac_fc_curl}" -fsSL --http1.1
                            --retry 3 --retry-all-errors --retry-delay 3
                            --connect-timeout 30 --max-time 600
                            -o "${_rac_fc_dest}" "${url}"
                    RESULT_VARIABLE _rac_fc_rc
                )
                if(_rac_fc_rc EQUAL 0 AND EXISTS "${_rac_fc_dest}")
                    set(_rac_fc_local TRUE)
                    break()
                endif()
                file(REMOVE "${_rac_fc_dest}")
                execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 4)
            endforeach()
        endif()
    endif()
    if(_rac_fc_local)
        FetchContent_Declare(
            ${name}
            URL "${_rac_fc_dest}"
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            ${ARGN}
        )
    else()
        message(STATUS "${name}: curl prefetch unavailable; FetchContent will download ${url}")
        FetchContent_Declare(
            ${name}
            URL ${url}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            ${ARGN}
        )
    endif()
    FetchContent_MakeAvailable(${name})
endmacro()

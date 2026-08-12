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
            # Every other flag used below predates 2014 (--http1.1 is 7.33.0,
            # --retry/--retry-delay are 7.12.3). --retry-all-errors is the one
            # outlier: curl 7.71.0, June 2020. Plenty of supported systems ship
            # older — Ubuntu 20.04 (7.68.0), RHEL/CentOS 8 (7.61.1), Debian 10
            # (7.64.0), macOS 11 (7.64.1), Windows Server 2019 (7.55.1) — and
            # curl does NOT ignore an option it does not know:
            #     curl: option --retry-all-errors: is unknown   -> exit 2
            # immediately, before any request. On those hosts all 8 attempts
            # would fail instantly, the macro would fall through to plain
            # FetchContent, and the HTTP/1.1 hardening this file exists to add
            # would be silently lost on exactly the older/self-hosted machines
            # that need it most (plus ~32s of pointless retry sleeps per
            # archive). Probe once and pass the flag only where it parses.
            if(NOT DEFINED _RAC_FC_CURL_RETRY_ALL)
                execute_process(
                    COMMAND "${_rac_fc_curl}" --version
                    OUTPUT_VARIABLE _rac_fc_curl_banner
                    ERROR_QUIET
                )
                set(_rac_fc_retry_all "")
                if(_rac_fc_curl_banner MATCHES "curl ([0-9]+\\.[0-9]+(\\.[0-9]+)?)")
                    if(CMAKE_MATCH_1 VERSION_GREATER_EQUAL "7.71.0")
                        set(_rac_fc_retry_all "--retry-all-errors")
                    else()
                        message(STATUS
                            "curl ${CMAKE_MATCH_1} predates 7.71.0; "
                            "omitting --retry-all-errors from archive prefetch")
                    endif()
                else()
                    message(STATUS
                        "could not parse `curl --version`; "
                        "omitting --retry-all-errors from archive prefetch")
                endif()
                # CACHE INTERNAL so the probe runs once per configure and is
                # visible to every scope that includes this file.
                set(_RAC_FC_CURL_RETRY_ALL "${_rac_fc_retry_all}" CACHE INTERNAL
                    "--retry-all-errors when the local curl is >= 7.71.0, else empty")
            endif()
            foreach(_rac_fc_attempt RANGE 1 8)
                message(STATUS "Downloading ${name} (attempt ${_rac_fc_attempt}/8): ${url}")
                # Unquoted expansion: an empty _RAC_FC_CURL_RETRY_ALL contributes
                # zero arguments rather than an empty one.
                execute_process(
                    COMMAND "${_rac_fc_curl}" -fsSL --http1.1
                            --retry 3 ${_RAC_FC_CURL_RETRY_ALL} --retry-delay 3
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

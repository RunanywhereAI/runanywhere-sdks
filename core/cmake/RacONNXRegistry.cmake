# Stage the pinned Microsoft ONNX Runtime packages when GitHub release assets
# are unavailable. All downloads are verified against core/VERSIONS before any
# package member is used.
include_guard(GLOBAL)
include(FetchContent)

function(rac_onnx_download_registry_archive output url filename sha256)
    if(DEFINED RAC_ONNX_PACKAGE_CACHE_DIR AND NOT "${RAC_ONNX_PACKAGE_CACHE_DIR}" STREQUAL "")
        set(cache_dir "${RAC_ONNX_PACKAGE_CACHE_DIR}")
    else()
        set(cache_dir "${CMAKE_BINARY_DIR}/_deps/onnxruntime-registry-archives")
    endif()
    file(MAKE_DIRECTORY "${cache_dir}")
    set(archive "${cache_dir}/${filename}")
    file(DOWNLOAD "${url}" "${archive}"
        EXPECTED_HASH "SHA256=${sha256}"
        TLS_VERIFY ON
        STATUS download_status
        INACTIVITY_TIMEOUT 30
        TIMEOUT 600
    )
    list(GET download_status 0 download_code)
    if(NOT download_code EQUAL 0)
        message(FATAL_ERROR "Could not fetch verified ONNX Runtime artifact ${url}: ${download_status}")
    endif()
    set(${output} "${archive}" PARENT_SCOPE)
endfunction()

function(rac_onnx_stage_nuget output rid version sha256)
    # Preserve FetchContent's source layout for the desktop kit and Electron
    # packagers, which also read native libraries from _deps/onnxruntime-src.
    set(stage "${CMAKE_BINARY_DIR}/_deps/onnxruntime-src")
    set(marker "${stage}/.artifact-identity")
    set(expected_identity "${rid} ${version} ${sha256}")
    if(rid STREQUAL "linux-x64" OR rid STREQUAL "linux-arm64")
        set(libraries libonnxruntime.so libonnxruntime_providers_shared.so)
        set(alias_name libonnxruntime.so.1)
    elseif(rid STREQUAL "osx-arm64")
        set(libraries libonnxruntime.dylib)
        set(alias_name libonnxruntime.1.dylib)
    elseif(rid STREQUAL "win-x64" OR rid STREQUAL "win-arm64")
        set(libraries onnxruntime.dll onnxruntime.lib
            onnxruntime_providers_shared.dll onnxruntime_providers_shared.lib)
        set(alias_name "")
    else()
        message(FATAL_ERROR "ONNX Runtime NuGet ${version} has no verified native payload for ${rid}")
    endif()

    if(EXISTS "${marker}")
        file(READ "${marker}" cached_identity)
        string(STRIP "${cached_identity}" cached_identity)
        if(cached_identity STREQUAL expected_identity)
            set(cache_complete TRUE)
            set(required_paths
                "${stage}/include/onnxruntime_c_api.h"
                "${stage}/include/onnxruntime_cxx_api.h")
            foreach(library IN LISTS libraries)
                list(APPEND required_paths "${stage}/lib/${library}")
            endforeach()
            if(NOT "${alias_name}" STREQUAL "")
                list(APPEND required_paths "${stage}/lib/${alias_name}")
            endif()
            if(rid STREQUAL "osx-arm64")
                list(APPEND required_paths "${stage}/include/coreml_provider_factory.h")
            endif()
            foreach(path IN LISTS required_paths)
                if(NOT EXISTS "${path}")
                    set(cache_complete FALSE)
                    break()
                endif()
            endforeach()
            if(cache_complete)
                set(${output} "${stage}" PARENT_SCOPE)
                return()
            endif()
        endif()
    endif()

    string(TOLOWER "${version}" package_version)
    rac_onnx_download_registry_archive(package
        "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${package_version}/microsoft.ml.onnxruntime.${package_version}.nupkg"
        "microsoft.ml.onnxruntime.${package_version}.nupkg" "${sha256}")

    file(REMOVE_RECURSE "${stage}")
    file(MAKE_DIRECTORY "${stage}/include" "${stage}/lib")
    set(package_patterns "build/native/include/*" "runtimes/${rid}/native/*")
    if(rid STREQUAL "osx-arm64")
        list(APPEND package_patterns "runtimes/ios/native/onnxruntime.xcframework.zip")
    endif()
    file(ARCHIVE_EXTRACT INPUT "${package}" DESTINATION "${stage}/package"
        PATTERNS ${package_patterns})

    file(GLOB headers "${stage}/package/build/native/include/*")
    if(NOT headers)
        message(FATAL_ERROR "Verified ONNX Runtime NuGet package has no native headers")
    endif()
    file(COPY ${headers} DESTINATION "${stage}/include")

    foreach(library IN LISTS libraries)
        set(source "${stage}/package/runtimes/${rid}/native/${library}")
        if(NOT EXISTS "${source}")
            message(FATAL_ERROR "Verified ONNX Runtime NuGet package lacks ${rid}/${library}")
        endif()
        file(COPY_FILE "${source}" "${stage}/lib/${library}")
    endforeach()
    if(NOT "${alias_name}" STREQUAL "")
        list(GET libraries 0 primary_library)
        file(CREATE_LINK "${primary_library}" "${stage}/lib/${alias_name}"
            SYMBOLIC COPY_ON_ERROR)
    endif()

    if(rid STREQUAL "osx-arm64")
        set(ios_zip "${stage}/package/runtimes/ios/native/onnxruntime.xcframework.zip")
        if(NOT EXISTS "${ios_zip}")
            message(FATAL_ERROR "Verified ONNX Runtime NuGet package lacks its iOS XCFramework")
        endif()
        if(NOT DEFINED RAC_ONNX_NUGET_IOS_SHA256)
            message(FATAL_ERROR "RAC_ONNX_NUGET_IOS_SHA256 is required for macOS CoreML headers")
        endif()
        file(SHA256 "${ios_zip}" actual_ios_sha256)
        if(NOT actual_ios_sha256 STREQUAL RAC_ONNX_NUGET_IOS_SHA256)
            message(FATAL_ERROR "ONNX Runtime NuGet iOS XCFramework checksum mismatch")
        endif()
        file(ARCHIVE_EXTRACT INPUT "${ios_zip}" DESTINATION "${stage}/ios"
            PATTERNS "onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers/coreml_provider_factory.h")
        set(coreml_header "${stage}/ios/onnxruntime.xcframework/ios-arm64/onnxruntime.framework/Headers/coreml_provider_factory.h")
        if(NOT EXISTS "${coreml_header}")
            message(FATAL_ERROR "Verified ONNX Runtime XCFramework lacks coreml_provider_factory.h")
        endif()
        file(COPY_FILE "${coreml_header}" "${stage}/include/coreml_provider_factory.h")
    endif()

    # Packagers scan this source tree for native libraries. Keep only the
    # normalized include/lib layout, without a second copy under package/.
    file(REMOVE_RECURSE "${stage}/package" "${stage}/ios")
    file(WRITE "${marker}" "${expected_identity}\n")
    set(${output} "${stage}" PARENT_SCOPE)
endfunction()

function(rac_onnx_stage_android_headers output version sha256)
    set(stage "${CMAKE_BINARY_DIR}/_deps/onnxruntime-android-headers-${version}")
    set(marker "${stage}/.artifact-sha256")
    if(EXISTS "${marker}")
        file(READ "${marker}" cached_sha256)
        string(STRIP "${cached_sha256}" cached_sha256)
        if(cached_sha256 STREQUAL sha256 AND
           EXISTS "${stage}/onnxruntime_cxx_api.h")
            set(${output} "${stage}" PARENT_SCOPE)
            return()
        endif()
    endif()

    rac_onnx_download_registry_archive(archive
        "https://repo.maven.apache.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/${version}/onnxruntime-android-${version}.aar"
        "onnxruntime-android-${version}.aar" "${sha256}")
    file(REMOVE_RECURSE "${stage}")
    file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${stage}/package"
        PATTERNS "headers/*")
    file(GLOB headers "${stage}/package/headers/*")
    if(NOT headers)
        message(FATAL_ERROR "Verified ONNX Runtime Android AAR has no headers")
    endif()
    file(MAKE_DIRECTORY "${stage}")
    file(COPY ${headers} DESTINATION "${stage}")
    if(NOT EXISTS "${stage}/onnxruntime_cxx_api.h")
        message(FATAL_ERROR "Verified ONNX Runtime Android AAR lacks C++ headers")
    endif()
    file(WRITE "${marker}" "${sha256}\n")
    set(${output} "${stage}" PARENT_SCOPE)
endfunction()

function(rac_onnx_fetch_release_or_nuget output release_url rid version sha256)
    # FetchContent and the registry stage share _deps/onnxruntime-src so
    # existing packagers keep working. Reuse a registry-marked tree before
    # asking FetchContent to populate the same source directory.
    if(EXISTS "${CMAKE_BINARY_DIR}/_deps/onnxruntime-src/.artifact-identity")
        rac_onnx_stage_nuget(registry_dir "${rid}" "${version}" "${sha256}")
        set(${output} "${registry_dir}" PARENT_SCOPE)
        return()
    endif()
    if(NOT RAC_ONNX_FORCE_REGISTRY)
        get_filename_component(filename "${release_url}" NAME)
        set(archive "${CMAKE_BINARY_DIR}/_deps/onnxruntime-release-archives/${filename}")
        get_filename_component(archive_dir "${archive}" DIRECTORY)
        file(MAKE_DIRECTORY "${archive_dir}")
        if(NOT EXISTS "${archive}")
            file(DOWNLOAD "${release_url}" "${archive}" TLS_VERIFY ON
                STATUS release_status INACTIVITY_TIMEOUT 30 TIMEOUT 600)
            list(GET release_status 0 release_code)
            if(NOT release_code EQUAL 0)
                file(REMOVE "${archive}")
                message(STATUS "ONNX Runtime release unavailable (${release_status}); using verified NuGet package")
            endif()
        endif()
        if(EXISTS "${archive}")
            FetchContent_Declare(onnxruntime URL "${archive}"
                DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
            FetchContent_MakeAvailable(onnxruntime)
            set(${output} "${onnxruntime_SOURCE_DIR}" PARENT_SCOPE)
            return()
        endif()
    endif()

    if(rid STREQUAL "osx-x64" OR rid STREQUAL "win-x86")
        message(FATAL_ERROR "ONNX Runtime ${version} NuGet has no ${rid} payload; the GitHub release asset is required for this architecture")
    endif()
    rac_onnx_stage_nuget(registry_dir "${rid}" "${version}" "${sha256}")
    set(${output} "${registry_dir}" PARENT_SCOPE)
endfunction()

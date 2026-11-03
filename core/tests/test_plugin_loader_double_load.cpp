/**
 * @file test_plugin_loader_double_load.cpp
 * @brief Verifies double-load is idempotent (registry dedups by name; the
 *        loader's redundant dlopen is balanced by an extra dlclose so the
 *        OS reference count stays at 1 after one explicit unload).
 */

#include <cstdio>
#include <cstring>

#include "../src/plugin/plugin_registry_internal.h"
#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"
#include "rac/plugin/rac_primitive.h"

#if (!defined(RAC_PLUGIN_MODE_STATIC) || !RAC_PLUGIN_MODE_STATIC) && !defined(_WIN32)
#include <dlfcn.h>
#endif

#ifndef RAC_TEST_PLUGIN_PATH
#error "RAC_TEST_PLUGIN_PATH must be set by tests/CMakeLists.txt"
#endif

int main() {
    std::fprintf(stdout, "test_plugin_loader_double_load: %s\n", RAC_TEST_PLUGIN_PATH);

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
    std::fprintf(stdout, "  skip: static-plugins build\n");
    return 0;
#else
    /* (1) First load → success. */
    rac_result_t rc = rac_registry_load_plugin(RAC_TEST_PLUGIN_PATH);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "first load failed: %d\n", static_cast<int>(rc));
        return 1;
    }
    size_t count_after_first = rac_registry_plugin_count();

    /* (2) Second load → registry dedups by metadata.name. The current dedup
     * policy returns RAC_ERROR_PLUGIN_DUPLICATE when the second registration
     * has lower priority; here it has equal priority so the registry MAY
     * accept (replace) it. Either outcome is acceptable; what matters is
     * that the count does not grow. */
    rc = rac_registry_load_plugin(RAC_TEST_PLUGIN_PATH);
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_PLUGIN_DUPLICATE) {
        std::fprintf(stderr, "second load returned unexpected code: %d\n", static_cast<int>(rc));
        return 1;
    }
    size_t count_after_second = rac_registry_plugin_count();
    if (count_after_second != count_after_first) {
        std::fprintf(stderr, "registry leaked: count after first=%zu, after second=%zu\n",
                     count_after_first, count_after_second);
        return 1;
    }

    // An attached manifest must survive a reload while the active vtable is leased.
    const auto* active = rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT);
    const rac_primitive_t primitive = RAC_PRIMITIVE_GENERATE_TEXT;
    rac_engine_manifest_t manifest{};
    manifest.name = active->metadata.name;
    manifest.display_name = active->metadata.display_name;
    manifest.version = active->metadata.engine_version;
    manifest.package_owner = "tests";
    manifest.package_name = "test_plugin";
    manifest.availability = RAC_ENGINE_AVAILABILITY_PUBLIC;
    manifest.priority = active->metadata.priority;
    manifest.primitives = &primitive;
    manifest.primitives_count = 1;
    const rac_engine_manifest_t* leased_manifest = nullptr;
    if (rac_engine_manifest_attach_vtable(&manifest, active) != RAC_SUCCESS ||
        rac_registry_load_plugin(RAC_TEST_PLUGIN_PATH) != RAC_SUCCESS ||
        rac_plugin_registry_acquire(active, &leased_manifest) != RAC_SUCCESS ||
        leased_manifest != &manifest) {
        std::fprintf(stderr, "could not attach/acquire fixture manifest\n");
        return 1;
    }
    // Low-level load/unload still expose BUSY; only registration consumers normalize it.
    if (rac_registry_load_plugin(RAC_TEST_PLUGIN_PATH) != RAC_ERROR_PLUGIN_BUSY ||
        rac_registry_unload_plugin("test_plugin") != RAC_ERROR_PLUGIN_BUSY) {
        std::fprintf(stderr, "leased plugin did not refuse replacement/unload\n");
        return 1;
    }
    const char* paths[] = {nullptr, "", RAC_TEST_PLUGIN_PATH, RAC_TEST_PLUGIN_PATH};
    size_t loaded = 0;
    if (rac_registry_load_plugins(paths, 4, &loaded) != RAC_SUCCESS || loaded != 2 ||
        rac_registry_plugin_count() != count_after_first ||
        rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != active ||
        rac_engine_manifest_find("test_plugin") != &manifest) {
        std::fprintf(stderr, "busy batch did not preserve availability, count or manifest\n");
        return 1;
    }
    rac_plugin_unavailable_t* unavailable = nullptr;
    size_t unavailable_count = 0;
    if (rac_registry_list_unavailable_plugins(&unavailable, &unavailable_count) != RAC_SUCCESS ||
        unavailable_count != 0) {
        std::fprintf(stderr, "busy backend was recorded as unavailable\n");
        return 1;
    }
    rac_registry_free_unavailable_plugins(unavailable, unavailable_count);
    // A genuinely missing plugin is still isolated, counted as a failure and reported.
    const char* mixed_paths[] = {"runanywhere_registration_missing_backend.invalid",
                                 RAC_TEST_PLUGIN_PATH};
    if (rac_registry_load_plugins(mixed_paths, 2, &loaded) != RAC_SUCCESS || loaded != 1 ||
        rac_registry_list_unavailable_plugins(&unavailable, &unavailable_count) != RAC_SUCCESS ||
        unavailable_count != 1 ||
        std::strcmp(unavailable[0].name, "registration_missing_backend") != 0 ||
        unavailable[0].status != RAC_ERROR_PLUGIN_LOAD_FAILED ||
        rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != active) {
        std::fprintf(stderr, "mixed batch swallowed failure or lost busy backend\n");
        return 1;
    }
    rac_registry_free_unavailable_plugins(unavailable, unavailable_count);
    rac_plugin_registry_release(active);

    /* (3) Single unregister suffices to remove the entry. */
    rc = rac_registry_unload_plugin("test_plugin");
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "unload failed: %d\n", static_cast<int>(rc));
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr, "still in registry after unload\n");
        return 1;
    }

    /* (3b) The redundant dlopen from step (2) must be balanced by an extra
     * dlclose inside rac_registry_load_plugin, otherwise the OS keeps the
     * library mapped after the single unload in step (3). On POSIX we can
     * confirm this with dlopen(RTLD_NOLOAD): it returns NULL if and only if
     * the library is no longer present in the process. We immediately
     * dlclose() any non-null result so the probe is side-effect free. */
#if !defined(_WIN32)
    void* probe = dlopen(RAC_TEST_PLUGIN_PATH, RTLD_NOLOAD | RTLD_LAZY);
    if (probe != nullptr) {
        std::fprintf(stderr,
                     "leak detected: '%s' is still mapped after one unload "
                     "following two loads (RTLD_NOLOAD returned %p)\n",
                     RAC_TEST_PLUGIN_PATH, probe);
        dlclose(probe);
        return 1;
    }
#endif

    /* (4) Unloading a name that no longer exists returns NOT_FOUND, never crash. */
    rc = rac_registry_unload_plugin("test_plugin");
    if (rc != RAC_ERROR_NOT_FOUND) {
        std::fprintf(stderr, "second unload returned unexpected: %d (want NOT_FOUND)\n",
                     static_cast<int>(rc));
        return 1;
    }

    std::fprintf(stdout, "  ok: double-load deduped, single unload sufficient\n");
    return 0;
#endif
}

//
//  RunAnywhere+PluginLoader.swift
//  RunAnywhere
//
//  v2 close-out (B31): Swift wrapper around `rac_registry_load_plugin`
//  so apps can dlopen third-party engine plugins at runtime on macOS /
//  Linux. On iOS the App Store bans dlopen of third-party libraries, so
//  every method here returns an `SDKException(featureNotAvailable)` —
//  bundle your engines via SwiftPM dependencies on iOS instead.
//
//  Mirrors GAP 03 dynamic plugin loading.
//

import CRACommons
import Foundation

extension RunAnywhere {

    /// Runtime plugin loader.
    ///
    /// Use to load a vendor-supplied engine library at runtime on
    /// platforms that allow `dlopen`:
    ///
    ///     try RunAnywhere.PluginLoader.load(at:
    ///         URL(fileURLWithPath: "/opt/runanywhere/plugins/librunanywhere_acmevoice.dylib"))
    ///
    /// On iOS, every call returns `SDKException(featureNotAvailable)` —
    /// link the engine at compile time via SwiftPM instead.
    public enum PluginLoader {

        /// Compile-time plugin API version this build of `RACommons`
        /// was built against. Use to gate which plugin libraries are
        /// loadable at all.
        public static var apiVersion: UInt32 {
            return rac_plugin_api_version()
        }

        /// Load a shared library at `url` and register the
        /// `rac_plugin_entry_<stem>` it exposes with the in-process
        /// plugin registry. Symbol-resolution convention:
        ///
        ///     librunanywhere_<name>.dylib  → rac_plugin_entry_<name>
        ///     librunanywhere_<name>.so     → rac_plugin_entry_<name>
        ///     runanywhere_<name>.dll       → rac_plugin_entry_<name>
        ///
        /// - Throws: `SDKException` with codes:
        ///   `.featureNotAvailable` (host built with `RAC_STATIC_PLUGINS=ON`,
        ///       typically iOS / WASM),
        ///   `.invalidConfiguration` (path resolution / dlopen failed),
        ///   `.invalidModelFormat` (ABI mismatch — plugin built against a
        ///       different `RAC_PLUGIN_API_VERSION`),
        ///   `.unsupportedModality` (plugin's `capability_check` declined),
        ///   `.alreadyInitialized` (a higher-priority plugin with the same
        ///       name is already registered),
        ///   `.unknown` for any other commons error.
        public static func load(at url: URL) throws {
            let path = url.path
            let result = path.withCString { rac_registry_load_plugin($0) }
            try throwIfFailed(result, op: "load", context: path)
        }

        /// Unregister a previously-loaded plugin and `dlclose` its
        /// underlying handle (statically-registered plugins stay linked).
        ///
        /// - Throws: `SDKException(.notImplemented)` (statically-registered),
        ///   `SDKException(.modelNotFound)` (plugin name unknown), or other
        ///   commons errors.
        public static func unload(name: String) throws {
            let result = name.withCString { rac_registry_unload_plugin($0) }
            try throwIfFailed(result, op: "unload", context: name)
        }

        /// Total number of plugins currently registered (one count per
        /// plugin, not per primitive).
        public static var registeredCount: Int {
            return rac_registry_plugin_count()
        }

        /// Snapshot of currently-registered plugin names.
        public static func registeredNames() -> [String] {
            var names: UnsafeMutablePointer<UnsafePointer<CChar>?>?
            var count: Int = 0
            let rc = rac_registry_list_plugins(&names, &count)
            guard rc == RAC_SUCCESS, let n = names else { return [] }
            defer { rac_registry_free_plugin_list(n, count) }
            var out: [String] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                if let cstr = n[i] {
                    out.append(String(cString: cstr))
                }
            }
            return out
        }

        // MARK: - Helpers

        private static func throwIfFailed(_ rc: rac_result_t, op: String, context: String) throws {
            guard rc != RAC_SUCCESS else { return }
            let suffix = " (PluginLoader.\(op): \(context))"
            switch rc {
            case RAC_ERROR_NULL_POINTER:
                throw SDKException.runtime(.invalidConfiguration, "Null path/name" + suffix)
            case RAC_ERROR_PLUGIN_LOAD_FAILED:
                throw SDKException.runtime(.invalidConfiguration,
                                       "dlopen / dlsym failed" + suffix)
            case RAC_ERROR_ABI_VERSION_MISMATCH:
                throw SDKException.runtime(.invalidModelFormat,
                                       "Plugin built against a different RAC_PLUGIN_API_VERSION " +
                                       "(host = \(apiVersion))" + suffix)
            case RAC_ERROR_CAPABILITY_UNSUPPORTED:
                throw SDKException.runtime(.unsupportedModality,
                                       "Plugin capability_check() declined" + suffix)
            case RAC_ERROR_PLUGIN_DUPLICATE:
                throw SDKException.runtime(.alreadyInitialized,
                                       "Plugin name already registered with higher priority" + suffix)
            case RAC_ERROR_FEATURE_NOT_AVAILABLE:
                throw SDKException.runtime(.featureNotAvailable,
                                       "Dynamic plugin loading not available — host built with " +
                                       "RAC_STATIC_PLUGINS=ON (typically iOS / WASM). Bundle the " +
                                       "engine at compile time instead." + suffix)
            case RAC_ERROR_NOT_FOUND:
                throw SDKException.runtime(.modelNotFound, "Plugin not registered" + suffix)
            case RAC_ERROR_PLUGIN_BUSY:
                throw SDKException.runtime(.notImplemented,
                                       "Plugin held by an active session (refcount wired in GAP 04+)" + suffix)
            default:
                throw SDKException.runtime(.unknown,
                                       "rac_registry_\(op)_plugin returned \(rc)" + suffix)
            }
        }
    }
}

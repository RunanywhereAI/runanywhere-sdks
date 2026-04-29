//
//  RunAnywhere+PluginLoader.swift
//  RunAnywhere
//
//  Public API for dynamic plugin loading (CANONICAL_API §12).
//  Exposes `RunAnywhere.pluginLoader.*` as a lowercase property accessor
//  backed by the C ABI (`rac_registry_*` symbols).
//
//  On iOS / WASM where `dlopen` is banned, every method returns an
//  `SDKException(featureNotAvailable)` — bundle engines via SwiftPM instead.
//

import CRACommons
import Foundation

// MARK: - PluginInfo

/// Information about a loaded plugin.
public struct PluginInfo: Sendable {
    /// The plugin name (library stem, e.g. "runanywhere_acmevoice")
    public let name: String

    /// The file-system path the plugin was loaded from
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

// MARK: - RunAnywhere.pluginLoader capability

public extension RunAnywhere {

    /// Capability accessor for runtime plugin management (CANONICAL_API §12).
    ///
    /// Usage:
    /// ```swift
    /// let info = try RunAnywhere.pluginLoader.load(path: "/opt/plugins/librunanywhere_acmevoice.dylib")
    /// RunAnywhere.pluginLoader.unload(name: info.name)
    /// ```
    static var pluginLoader: PluginLoaderNamespace { PluginLoaderNamespace() }

    /// Stateless namespace for plugin-loader operations.
    /// Backed by the `rac_registry_*` C ABI.
    struct PluginLoaderNamespace: Sendable {

        fileprivate init() {}

        /// Compile-time plugin API version this build of `RACommons` was built
        /// against. Gate on this before loading third-party plugin binaries.
        public var apiVersion: UInt32 {
            rac_plugin_api_version()
        }

        /// Load a shared library at `path` and register the
        /// `rac_plugin_entry_<stem>` it exposes with the in-process
        /// plugin registry.
        ///
        /// Symbol-resolution convention:
        /// ```
        /// librunanywhere_<name>.dylib  → rac_plugin_entry_<name>
        /// librunanywhere_<name>.so     → rac_plugin_entry_<name>
        /// runanywhere_<name>.dll       → rac_plugin_entry_<name>
        /// ```
        ///
        /// - Parameter path: Absolute or relative path to the shared library.
        /// - Returns: `PluginInfo` describing the loaded plugin.
        /// - Throws: `SDKException` on failure (see error codes below).
        @discardableResult
        public func load(path: String) throws -> PluginInfo {
            let result = path.withCString { rac_registry_load_plugin($0) }
            try throwIfFailed(result, op: "load", context: path)

            // Derive the plugin name from the library stem.
            let stem = URL(fileURLWithPath: path)
                .deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "lib", with: "", range:
                    URL(fileURLWithPath: path)
                        .deletingPathExtension()
                        .lastPathComponent
                        .range(of: "^lib", options: .regularExpression)
                )
            return PluginInfo(name: stem, path: path)
        }

        /// Unregister a previously-loaded plugin and `dlclose` its handle.
        ///
        /// - Parameter name: The plugin name (library stem).
        /// - Throws: `SDKException` on failure.
        public func unload(name: String) throws {
            let result = name.withCString { rac_registry_unload_plugin($0) }
            try throwIfFailed(result, op: "unload", context: name)
        }

        /// Total number of plugins currently registered.
        public var registeredCount: Int {
            rac_registry_plugin_count()
        }

        /// Snapshot of currently-registered plugin names.
        public func registeredNames() -> [String] {
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

        /// Snapshot of all currently-loaded plugins.
        ///
        /// Returned `PluginInfo` contains the plugin name only; the original
        /// load path is not persisted by the C registry. Use `registeredNames()`
        /// if only names are needed.
        public func listLoaded() -> [PluginInfo] {
            registeredNames().map { PluginInfo(name: $0, path: "") }
        }

        // MARK: - Private helpers

        private func throwIfFailed(_ rc: rac_result_t, op: String, context: String) throws {
            guard rc != RAC_SUCCESS else { return }
            let suffix = " (pluginLoader.\(op): \(context))"
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
                                           "Plugin held by an active session" + suffix)
            default:
                throw SDKException.runtime(.unknown,
                                           "rac_registry_\(op)_plugin returned \(rc)" + suffix)
            }
        }
    }
}

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

/// Information about a loaded plugin. Backed by the generated `RAPluginInfo`
/// proto (`{name, path}`), shared cross-SDK. Helper to build one locally.
private func makePluginInfo(name: String, path: String) -> RAPluginInfo {
    var info = RAPluginInfo()
    info.name = name
    info.path = path
    return info
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
        /// - Returns: `RAPluginInfo` describing the loaded plugin. The `name`
        ///            is the actual registry key (vt->metadata.name), so
        ///            `unload(name: info.name)` always matches.
        /// - Throws: `SDKException` on failure (see error codes below).
        @discardableResult
        public func load(path: String) throws -> RAPluginInfo {
            // Snapshot existing registry keys so we can identify the newly
            // registered name after load. The C loader stores the plugin
            // under vt->metadata.name (e.g. "llamacpp" for the in-tree
            // librunanywhere_llamacpp.dylib), which is what
            // rac_registry_unload_plugin expects. Deriving the name from
            // the file stem locally is fragile because the C++ loader also
            // strips an optional `runanywhere_` infix, and third-party
            // plugins may set metadata.name to anything they choose.
            let before = Set(registeredNames())

            let result = path.withCString { rac_registry_load_plugin($0) }
            try throwIfFailed(result, op: "load", context: path)

            let after = registeredNames()
            let registeredName = after.first { !before.contains($0) } ?? deriveStemName(path: path)
            return makePluginInfo(name: registeredName, path: path)
        }

        /// Mirror the C loader's stem derivation (strip directory, the
        /// optional `lib` prefix, the file extension, and the optional
        /// `runanywhere_` infix). Used as a last-resort fallback when the
        /// registry-diff is empty — e.g. when an already-loaded plugin's
        /// entry is idempotently re-registered and `registeredNames()`
        /// returns the same set.
        private func deriveStemName(path: String) -> String {
            var stem = URL(fileURLWithPath: path)
                .deletingPathExtension()
                .lastPathComponent
            if stem.hasPrefix("lib") {
                stem.removeFirst("lib".count)
            }
            if stem.hasPrefix("runanywhere_") {
                stem.removeFirst("runanywhere_".count)
            }
            return stem
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
            guard rc == RAC_SUCCESS, let buffer = names else { return [] }
            defer { rac_registry_free_plugin_list(buffer, count) }
            var out: [String] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                if let cstr = buffer[i] {
                    out.append(String(cString: cstr))
                }
            }
            return out
        }

        /// Snapshot of all currently-loaded plugins.
        ///
        /// Returned `RAPluginInfo` contains the plugin name only; the original
        /// load path is not persisted by the C registry (proto3 `path` defaults
        /// to ""). Use `registeredNames()` if only names are needed.
        public func listLoaded() -> [RAPluginInfo] {
            registeredNames().map { makePluginInfo(name: $0, path: "") }
        }

        // MARK: - Private helpers

        /// Delegate plugin-error classification to the commons ABI
        /// (`rac_result_to_proto_error`) via `SDKException.from(rcResult:)`,
        /// then enrich the message with the operation context so logs still
        /// say "(pluginLoader.load: /path/x.dylib)".
        private func throwIfFailed(_ rc: rac_result_t, op: String, context: String) throws {
            guard let exception = SDKException.from(rcResult: rc) else { return }
            var proto = exception.proto
            proto.message = "\(proto.message) (pluginLoader.\(op): \(context))"
            throw SDKException(proto: proto, underlying: exception.underlying)
        }
    }
}

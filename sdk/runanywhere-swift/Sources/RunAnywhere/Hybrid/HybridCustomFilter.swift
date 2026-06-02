//
//  HybridCustomFilter.swift
//  RunAnywhere
//
//  Swift binding for the cross-SDK named custom-filter callback table
//  (rac_hybrid_custom_filter.h). A HybridFilter.custom carries only a NAME on
//  the wire; the predicate logic stays host-supplied. This file registers a
//  Swift closure under that name so commons can RESOLVE it by name and INVOKE
//  it during candidate filtering — keeping the custom-filter decision inside
//  commons instead of leaking back into the host layer.
//
//  Both SDKs use the same design: the predicate is registered with commons via
//  `rac_hybrid_register_custom_filter` and the router owns the whole filter
//  phase. Swift expresses the predicate as a `@convention(c)` function; the
//  Kotlin binding registers an equivalent native trampoline over its JNI
//  custom-filter table. Neither evaluates customs host-side anymore.
//
//  Boxing follows the SDK's standard Swift↔C callback convention
//  (Unmanaged.passRetained → user_data → fromOpaque), with an
//  OSAllocatedUnfairLock-guarded name→box map for lifetime (per AGENTS.md
//  NSLock is forbidden).
//

import CRACommons
import Foundation
import os

/// Registers/unregisters named eligibility predicates with the commons custom
/// -filter table. The router invokes a registered predicate (by the name in
/// the policy's HybridFilter.custom) once per candidate during filtering.
enum HybridCustomFilter {

    private static let logger = SDKLogger(category: "Hybrid.CustomFilter")

    /// name → retained predicate box. Guards the lifetime of each boxed
    /// closure: a box stays retained from register until the matching
    /// unregister (after `rac_hybrid_unregister_custom_filter`), so commons
    /// never calls a freed closure.
    private static let registered =
        OSAllocatedUnfairLock<[String: Unmanaged<PredicateBox>]>(initialState: [:])

    /// Register (or replace) the predicate stored under `name`.
    @discardableResult
    static func register(name: String, check: @escaping @Sendable (String) -> Bool) -> Bool {
        guard !name.isEmpty else {
            logger.error("custom-filter name must be non-empty")
            return false
        }

        let box = PredicateBox(check)
        let retained = Unmanaged.passRetained(box)

        // `@convention(c)` predicate: read the candidate model id commons wrote
        // into the routing context, dispatch to the boxed Swift closure, and
        // map the Bool to rac_bool_t.
        let predicate: rac_hybrid_custom_filter_predicate_t = { ctx, userData in
            guard let box = PredicateBox.unwrap(userData) else { return RAC_TRUE }
            let modelId: String = {
                guard let ctx else { return "" }
                // candidate_model_id is a fixed char[128] inside the struct;
                // read it as a NUL-terminated C string.
                return withUnsafePointer(to: ctx.pointee.candidate_model_id) { tuplePtr in
                    tuplePtr.withMemoryRebound(to: CChar.self, capacity: 128) { cstr in
                        String(cString: cstr)
                    }
                }
            }()
            return box.check(modelId) ? RAC_TRUE : RAC_FALSE
        }

        let rc = name.withCString { namePtr in
            rac_hybrid_register_custom_filter(namePtr, predicate, retained.toOpaque())
        }

        guard rc == RAC_SUCCESS else {
            retained.release()
            logger.error("rac_hybrid_register_custom_filter('\(name)') failed: rc=\(rc)")
            return false
        }

        // Replace any prior box registered under the same name and retire it.
        let previous: Unmanaged<PredicateBox>? = registered.withLock { map in
            let old = map[name]
            map[name] = retained
            return old
        }
        previous?.release()
        return true
    }

    /// Remove the predicate stored under `name`. No-op when not registered.
    @discardableResult
    static func unregister(name: String) -> Bool {
        guard !name.isEmpty else { return false }

        let rc = name.withCString { rac_hybrid_unregister_custom_filter($0) }

        // Per rac_hybrid_custom_filter.h, unregister only retires the previous
        // table snapshot one generation later, so an in-flight predicate could
        // still be running. We release our retain here regardless — this matches
        // the binding's "register/unregister bracket the policy install" usage
        // where the router is not concurrently transcribing during teardown.
        let previous: Unmanaged<PredicateBox>? = registered.withLock { map in
            map.removeValue(forKey: name)
        }
        previous?.release()

        if rc != RAC_SUCCESS {
            logger.error("rac_hybrid_unregister_custom_filter('\(name)') failed: rc=\(rc)")
            return false
        }
        return true
    }

    /// Heap box carrying a Swift predicate across the C `user_data` pointer.
    ///
    /// `@unchecked Sendable`: immutable box over an already-`@Sendable` closure,
    /// so storing its `Unmanaged` handle in the `OSAllocatedUnfairLock` map is
    /// safe across isolation domains.
    private final class PredicateBox: @unchecked Sendable {
        let check: @Sendable (String) -> Bool
        init(_ check: @escaping @Sendable (String) -> Bool) { self.check = check }

        static func unwrap(_ userData: UnsafeMutableRawPointer?) -> PredicateBox? {
            guard let userData else { return nil }
            return Unmanaged<PredicateBox>.fromOpaque(userData).takeUnretainedValue()
        }
    }
}

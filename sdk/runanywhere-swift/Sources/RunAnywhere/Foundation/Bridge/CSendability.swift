//
//  CSendability.swift
//  RunAnywhere SDK
//
//  Retroactive `Sendable` conformances for the opaque C pointer types used
//  throughout the bridge surface.
//
//  Background
//  ----------
//  The Swift standard library treats `OpaquePointer`, `UnsafeMutableRawPointer`,
//  and `UnsafeRawPointer` as non-Sendable by default because their thread
//  safety is defined by whoever owns the memory they point at. In the Swift 6
//  language mode, capturing one of these pointers inside a `@Sendable` closure
//  (e.g. `AsyncStream.Continuation.onTermination`, `Task.detached`,
//  `OSAllocatedUnfairLock.withLock`) is therefore a compile error.
//
//  Safety Argument
//  ---------------
//  For this SDK the owner of every opaque pointer is the C core
//  (`runanywhere-commons`). The commons layer guarantees each opaque handle
//  is safe to use from any thread as long as the caller honors the
//  component's lifecycle contract (create → use → destroy). The Swift layer
//  only threads these pointers through `@convention(c)` trampolines and
//  `Unmanaged` retain/release pairs; it never dereferences them.
//
//  Under those rules it is safe — and necessary, for Swift 6 language mode —
//  to mark the three pointer types as `@unchecked Sendable`.
//
//  `@retroactive` is required on Swift 6 when conforming a type that lives
//  in a different module (here, `Swift`) to a protocol from another module.
//  Without it, Swift 6 warns/errors that a future standard-library update
//  could introduce its own conformance that would conflict with ours.
//

import Foundation


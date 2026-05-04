//
//  LLMHelpers.swift
//  RunAnywhere SDK
//
//  SDK-unique helper types for LLM text generation that are NOT covered by
//  any proto schema in `idl/llm_*.proto`. Per CANONICAL_API §3 / §15:
//    - Proto-overlapping types live in (or behind a typealias from)
//      `Generated/llm_*.pb.swift` as `RALLMGenerationOptions`,
//      `RALLMGenerationResult`, `RALLMConfiguration`, etc.
//    - SDK-unique helpers (Generatable protocol, StreamAccumulator actor,
//      thinking-tag pattern wrapper) live HERE so the public surface stays
//      proto-anchored.
//
//  The `LLMTypes.swift` file is being held in place during the v2 cross-SDK
//  parity migration because its hand-rolled wrappers expose
//  `withCOptions`/`init(from cResult:)` C bridge methods that the active
//  `CppBridge.LLM` callers depend on. As soon as those bridges are
//  rewritten against the proto types directly, `LLMTypes.swift` can be
//  fully deleted and the helpers below move into the public root.
//

import Foundation

//
//  CppBridge+ImageEmbedding.swift
//  RunAnywhere SDK
//
//  Image embedding (`RAC_PRIMITIVE_EMBED_IMAGE`) — pixels in, one vector out.
//
//  Unlike every other bridge in this directory this one is NOT proto-based. The commons entry
//  points are the plain C service verbs `rac_image_embedding_create/_initialize/_embed/_destroy`,
//  the same standalone-service shape rerank uses under the hood, because the payload is a decoded
//  pixel buffer: routing megabytes of RGB through a proto round trip would copy them twice for no
//  benefit, and the result type is the text path's `rac_embeddings_result_t` already.
//
//  Every symbol is resolved lazily via `dlsym`, exactly as CppBridge+Rerank does, so the Swift SDK
//  still compiles and links against a prebuilt RACommons that predates the ABI-v10 export set.
//  Calling into it against such a binary throws rather than crashing.
//

import CRACommons
import Foundation

private enum ImageEmbeddingABI {
    typealias Create = @convention(c) (
        UnsafePointer<CChar>?, UnsafeMutablePointer<rac_handle_t?>?
    ) -> rac_result_t
    typealias Initialize = @convention(c) (rac_handle_t?, UnsafePointer<CChar>?) -> rac_result_t
    typealias Embed = @convention(c) (
        rac_handle_t?,
        UnsafePointer<rac_image_embedding_input_t>?,
        UnsafeMutablePointer<rac_embeddings_result_t>?
    ) -> rac_result_t
    typealias ResultFree = @convention(c) (UnsafeMutablePointer<rac_embeddings_result_t>?) -> Void
    typealias Destroy = @convention(c) (rac_handle_t?) -> Void

    static let create = NativeProtoABI.load("rac_image_embedding_create", as: Create.self)
    static let initialize = NativeProtoABI.load("rac_image_embedding_initialize", as: Initialize.self)
    static let embed = NativeProtoABI.load("rac_image_embedding_embed", as: Embed.self)
    static let resultFree = NativeProtoABI.load("rac_embeddings_result_free", as: ResultFree.self)
    static let destroy = NativeProtoABI.load("rac_image_embedding_destroy", as: Destroy.self)

    /// All five entry points, or nil when the linked RACommons predates the ABI-v10 export set.
    ///
    /// Resolved as a group rather than checked individually so the call site binds them once with
    /// `guard let` -- five `!`s guarded by a separate `isAvailable` flag is the same bug shape as
    /// a TOCTOU check, and SwiftLint's `force_unwrapping` rule is right to reject it.
    struct Resolved {
        let create: Create
        let initialize: Initialize
        let embed: Embed
        let resultFree: ResultFree
        let destroy: Destroy
    }

    static var resolved: Resolved? {
        guard let create, let initialize, let embed, let resultFree, let destroy else {
            return nil
        }
        return Resolved(
            create: create,
            initialize: initialize,
            embed: embed,
            resultFree: resultFree,
            destroy: destroy
        )
    }
}

extension CppBridge {

    /// Direct-C bridge for `RAC_PRIMITIVE_EMBED_IMAGE`.
    enum ImageEmbedding {

        /// Embed one decoded RGB8 image with the model at `modelPath`.
        ///
        /// The handle is created, used and destroyed inside this call. That is deliberate for the
        /// first cut: a vision tower's `initialize` is the expensive step, so a long-lived handle
        /// is worth having — but caching one here would need the same owner-scoped lifetime rules
        /// the rerank component bridge carries, and getting that wrong leaks a Core ML model.
        static func embed(
            modelPath: String,
            pixels: Data,
            width: Int,
            height: Int
        ) throws -> [Float] {
            guard let abi = ImageEmbeddingABI.resolved else {
                throw SDKException(
                    code: .notInitialized,
                    message: NativeProtoABI.missingSymbolMessage("rac_image_embedding_embed"),
                    category: .component
                )
            }
            guard width > 0, height > 0 else {
                throw SDKException(
                    code: .invalidParameter,
                    message: "image width and height must be positive",
                    category: .validation
                )
            }
            // The engine reads exactly width*height*3 bytes. A short buffer would be read past its
            // end, so check here rather than trusting the caller's arithmetic.
            let expected = width * height * 3
            guard pixels.count >= expected else {
                throw SDKException(
                    code: .invalidParameter,
                    message: "packed RGB buffer is \(pixels.count) bytes, expected \(expected)",
                    category: .validation
                )
            }

            var handle: rac_handle_t?
            let createRC = modelPath.withCString { abi.create($0, &handle) }
            guard createRC == RAC_SUCCESS, let live = handle else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "rac_image_embedding_create failed (\(createRC))",
                    category: .component
                )
            }
            defer { abi.destroy(live) }

            let initRC = modelPath.withCString { abi.initialize(live, $0) }
            guard initRC == RAC_SUCCESS else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "rac_image_embedding_initialize failed (\(initRC))",
                    category: .model
                )
            }

            var out = rac_embeddings_result_t()
            let embedRC: rac_result_t = pixels.withUnsafeBytes { raw -> rac_result_t in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return RAC_ERROR_NULL_POINTER
                }
                var input = rac_image_embedding_input_t()
                input.format = RAC_IMAGE_EMBEDDING_FORMAT_RGB8
                input.pixels = base
                input.width = UInt32(width)
                input.height = UInt32(height)
                return withUnsafePointer(to: &input) {
                    abi.embed(live, $0, &out)
                }
            }
            guard embedRC == RAC_SUCCESS else {
                abi.resultFree(&out)
                throw SDKException(
                    code: .inferenceFailed,
                    message: "rac_image_embedding_embed failed (\(embedRC))",
                    category: .component
                )
            }
            defer { abi.resultFree(&out) }

            guard out.num_embeddings > 0, let vectors = out.embeddings,
                  let data = vectors[0].data, vectors[0].dimension > 0 else {
                throw SDKException(
                    code: .inferenceFailed,
                    message: "image embedding returned no vector",
                    category: .component
                )
            }
            return Array(UnsafeBufferPointer(start: data, count: Int(vectors[0].dimension)))
        }
    }
}

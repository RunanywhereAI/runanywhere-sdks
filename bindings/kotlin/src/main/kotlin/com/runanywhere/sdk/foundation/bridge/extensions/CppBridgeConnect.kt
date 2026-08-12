/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ConnectClientHello
import ai.runanywhere.proto.v1.ConnectClientSessionState
import ai.runanywhere.proto.v1.ConnectClientStartRequest
import ai.runanywhere.proto.v1.ConnectHandshakeResponse
import ai.runanywhere.proto.v1.ConnectPlatformPolicy
import ai.runanywhere.proto.v1.ConnectPlatformPolicyRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/** Thin protobuf facade over the commons-owned Connect policy and handshake ABI. */
internal object CppBridgeConnect {
    fun platformPolicy(request: ConnectPlatformPolicyRequest): ConnectPlatformPolicy =
        decode(
            bytes =
                RunAnywhereBridge.racConnectGetPlatformPolicyProto(
                    ConnectPlatformPolicyRequest.ADAPTER.encode(request),
                ),
            operation = "read Connect platform policy",
            decode = ConnectPlatformPolicy.ADAPTER::decode,
        )

    fun createClientHello(request: ConnectClientStartRequest): ConnectClientHello =
        decode(
            bytes =
                RunAnywhereBridge.racConnectClientCreateHelloProto(
                    ConnectClientStartRequest.ADAPTER.encode(request),
                ),
            operation = "create Connect client hello",
            decode = ConnectClientHello.ADAPTER::decode,
        )

    fun validateHost(response: ConnectHandshakeResponse): ConnectClientSessionState =
        decode(
            bytes =
                RunAnywhereBridge.racConnectClientValidateHostProto(
                    ConnectHandshakeResponse.ADAPTER.encode(response),
                ),
            operation = "validate Connect host",
            decode = ConnectClientSessionState.ADAPTER::decode,
        )

    private fun <T> decode(
        bytes: ByteArray?,
        operation: String,
        decode: (ByteArray) -> T,
    ): T {
        if (bytes == null) {
            throw SDKException.networkError("Unable to $operation")
        }
        return try {
            decode(bytes)
        } catch (error: Exception) {
            throw SDKException.networkError("Unable to $operation", error)
        }
    }
}

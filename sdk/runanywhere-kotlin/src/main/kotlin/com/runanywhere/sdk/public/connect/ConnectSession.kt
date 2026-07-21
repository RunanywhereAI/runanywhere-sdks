/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.connect

import ai.runanywhere.proto.v1.ConnectClientStartRequest
import ai.runanywhere.proto.v1.ConnectInvocationRequest
import ai.runanywhere.proto.v1.ConnectPlatform
import ai.runanywhere.proto.v1.ConnectPlatformPolicyRequest
import ai.runanywhere.proto.v1.ConnectRoleAvailability
import ai.runanywhere.proto.v1.ConnectSessionState
import android.content.Context
import android.os.Build
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeConnect
import com.runanywhere.sdk.foundation.connect.AndroidConnectDiscovery
import com.runanywhere.sdk.foundation.connect.AndroidConnectEndpoint
import com.runanywhere.sdk.foundation.connect.AndroidConnectSocket
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMStreamEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID

/** A runtime host discovered on the Android device's local network. */
data class ConnectHost(
    val id: String,
    val displayName: String,
    val protocolVersion: Int,
)

/** The single language model selected and published by the connected host. */
data class ConnectModel(
    val id: String,
    val displayName: String,
    val framework: String,
    val contextWindow: Int,
    val supportsStreaming: Boolean,
)

enum class ConnectStatus {
    IDLE,
    DISCOVERING,
    CONNECTING,
    CONNECTED,
    DISCONNECTED,
    FAILED,
}

/** One observable snapshot for discovery, connection, model, and failure UI. */
data class ConnectState(
    val status: ConnectStatus = ConnectStatus.IDLE,
    val availableHosts: List<ConnectHost> = emptyList(),
    val connectingHost: ConnectHost? = null,
    val activeHost: ConnectHost? = null,
    val activeModel: ConnectModel? = null,
    val lastDisconnectedHost: ConnectHost? = null,
    val lastDisconnectedModel: ConnectModel? = null,
    val message: String? = null,
) {
    val isConnected: Boolean get() = status == ConnectStatus.CONNECTED
}

/**
 * Android client for a RunAnywhere language model published by a host.
 *
 * Discovery is opt-in: creating a session never touches the local network.
 * Call [startBrowsing] only after the user selects the Connect entry point.
 * Commons remains authoritative for role policy, protocol negotiation, and
 * model binding; Android owns NSD and the framed TCP channel.
 */
class ConnectSession(
    context: Context,
) {
    private val applicationContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val endpointsLock = Any()
    private val endpoints = mutableMapOf<String, AndroidConnectEndpoint>()
    private val clientInstanceId = UUID.randomUUID().toString()

    private val _state = MutableStateFlow(ConnectState())
    val state: StateFlow<ConnectState> = _state.asStateFlow()

    private val socket = AndroidConnectSocket(scope, ::handleDisconnect)
    private val discovery =
        AndroidConnectDiscovery(
            context = applicationContext,
            onEndpointsChanged = ::handleEndpointsChanged,
            onFailure = ::handleFailure,
        )

    private var activeSessionId: String? = null

    /** Begin Android NSD discovery. This is the point that may trigger local-network permission UI. */
    suspend fun startBrowsing() {
        requireInitialized()
        val policy =
            CppBridgeConnect.platformPolicy(
                ConnectPlatformPolicyRequest(platform = ConnectPlatform.CONNECT_PLATFORM_ANDROID),
            )
        if (policy.client_role != ConnectRoleAvailability.CONNECT_ROLE_AVAILABILITY_ENABLED) {
            throw SDKException.invalidState("Connect client support is not enabled for Android")
        }

        _state.update { current ->
            current.copy(
                status = if (current.isConnected) current.status else ConnectStatus.DISCOVERING,
                message = null,
            )
        }
        try {
            discovery.start()
        } catch (error: Throwable) {
            handleFailure(error)
            throw error
        }
    }

    /** Stop discovery without ending an established hosted-model session. */
    fun stopBrowsing() {
        discovery.stop()
        _state.update { current ->
            if (current.status == ConnectStatus.DISCOVERING) {
                current.copy(status = ConnectStatus.IDLE, availableHosts = emptyList())
            } else {
                current.copy(availableHosts = emptyList())
            }
        }
    }

    /** Connect to a discovered host and adopt its selected model. */
    suspend fun connect(host: ConnectHost) {
        requireInitialized()
        val endpoint =
            synchronized(endpointsLock) { endpoints[host.id] }
                ?: throw SDKException.networkError("The selected host is no longer available")

        socket.close(notify = false)
        activeSessionId = null
        _state.update {
            it.copy(
                status = ConnectStatus.CONNECTING,
                connectingHost = host,
                activeHost = null,
                activeModel = null,
                message = null,
            )
        }

        try {
            val baseHello =
                CppBridgeConnect.createClientHello(
                    ConnectClientStartRequest(
                        display_name = androidDisplayName(),
                        platform = ConnectPlatform.CONNECT_PLATFORM_ANDROID,
                        protocol_version = PROTOCOL_VERSION,
                    ),
                )
            val response =
                socket.connect(
                    endpoint = endpoint,
                    hello = baseHello.copy(instance_id = clientInstanceId),
                )
            val session = CppBridgeConnect.validateHost(response)
            val hostMetadata = session.host
            val modelDescriptor = session.model
            if (
                session.state != ConnectSessionState.CONNECT_SESSION_STATE_CONNECTED ||
                session.session_id.isBlank() ||
                hostMetadata == null ||
                modelDescriptor == null ||
                modelDescriptor.model_id.isBlank()
            ) {
                throw SDKException.networkError(
                    session.error_message.ifBlank {
                        "The selected host could not provide a language model"
                    },
                )
            }

            val connectedHost =
                ConnectHost(
                    id = host.id,
                    displayName = hostMetadata.display_name.ifBlank { host.displayName },
                    protocolVersion = hostMetadata.protocol_version,
                )
            val connectedModel =
                ConnectModel(
                    id = modelDescriptor.model_id,
                    displayName = modelDescriptor.display_name,
                    framework = modelDescriptor.framework,
                    contextWindow = modelDescriptor.context_window,
                    supportsStreaming = modelDescriptor.supports_streaming,
                )
            activeSessionId = session.session_id
            _state.update {
                it.copy(
                    status = ConnectStatus.CONNECTED,
                    connectingHost = null,
                    activeHost = connectedHost,
                    activeModel = connectedModel,
                    lastDisconnectedHost = null,
                    lastDisconnectedModel = null,
                    message = null,
                )
            }
            socket.startHeartbeat(session.session_id)
        } catch (error: Throwable) {
            socket.close(notify = false)
            activeSessionId = null
            val message = error.message ?: "Unable to connect to the selected host"
            _state.update {
                it.copy(
                    status = ConnectStatus.FAILED,
                    connectingHost = null,
                    activeHost = null,
                    activeModel = null,
                    message = message,
                )
            }
            throw error
        }
    }

    /** Run text generation on the active host model without loading a local model. */
    fun generateStream(request: RALLMGenerateRequest): Flow<RALLMStreamEvent> {
        val snapshot = _state.value
        val sessionId = activeSessionId
        val model = snapshot.activeModel
        if (snapshot.status != ConnectStatus.CONNECTED || sessionId.isNullOrBlank() || model == null) {
            throw SDKException.networkError("Connect to a host before generating text")
        }
        val requestId = request.request_id.ifBlank { UUID.randomUUID().toString() }
        val generation = request.copy(request_id = requestId, model_id = model.id)
        return socket.generate(
            ConnectInvocationRequest(
                session_id = sessionId,
                request_id = requestId,
                generation = generation,
            ),
        )
    }

    /** End the active connection while leaving the session reusable. */
    fun disconnect() {
        socket.close(notify = false)
        activeSessionId = null
        _state.update {
            it.copy(
                status = ConnectStatus.IDLE,
                connectingHost = null,
                activeHost = null,
                activeModel = null,
                lastDisconnectedHost = null,
                lastDisconnectedModel = null,
                message = null,
            )
        }
    }

    /** Release discovery and connection resources. */
    fun stop() {
        discovery.stop()
        socket.close(notify = false)
        activeSessionId = null
        synchronized(endpointsLock) { endpoints.clear() }
        _state.value = ConnectState()
        scope.cancel()
    }

    private fun handleEndpointsChanged(resolved: List<AndroidConnectEndpoint>) {
        synchronized(endpointsLock) {
            endpoints.clear()
            resolved.associateByTo(endpoints) { it.id }
        }
        val hosts =
            resolved.map {
                ConnectHost(
                    id = it.id,
                    displayName = it.displayName,
                    protocolVersion = PROTOCOL_VERSION,
                )
            }
        _state.update { it.copy(availableHosts = hosts) }
    }

    private fun handleDisconnect(error: Throwable) {
        val previous = _state.value
        if (previous.status != ConnectStatus.CONNECTED) return
        activeSessionId = null
        val host = previous.activeHost
        val model = previous.activeModel
        val reason = disconnectMessage(error, host)
        _state.update {
            it.copy(
                status = ConnectStatus.DISCONNECTED,
                connectingHost = null,
                activeHost = null,
                activeModel = null,
                lastDisconnectedHost = host,
                lastDisconnectedModel = model,
                message = reason,
            )
        }
    }

    private fun handleFailure(error: Throwable) {
        if (_state.value.status == ConnectStatus.CONNECTED) {
            socket.close(notify = false)
            handleDisconnect(error)
            return
        }
        _state.update {
            it.copy(
                status = ConnectStatus.FAILED,
                connectingHost = null,
                message = error.message ?: "Connect failed",
            )
        }
    }

    private fun disconnectMessage(error: Throwable, host: ConnectHost?): String {
        val hostName = host?.displayName ?: "the host"
        val detail = error.message?.trim().orEmpty()
        return if (detail.isBlank() || detail == "The connection to the host ended") {
            "Connection to $hostName ended. The host may have stopped or left the network."
        } else {
            "Connection to $hostName ended: $detail"
        }
    }

    private fun requireInitialized() {
        if (!RunAnywhere.isInitialized) {
            throw SDKException.notInitialized("RunAnywhere Connect")
        }
    }

    private fun androidDisplayName(): String {
        val candidate =
            listOf(Build.MANUFACTURER, Build.MODEL)
                .filter { it.isNotBlank() }
                .joinToString(" ")
                .trim()
        return candidate.take(128).ifBlank { "Android device" }
    }

    private companion object {
        const val PROTOCOL_VERSION = 1
    }
}

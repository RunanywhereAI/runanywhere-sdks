/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.connect

import ai.runanywhere.proto.v1.ConnectClientFrame
import ai.runanywhere.proto.v1.ConnectClientHello
import ai.runanywhere.proto.v1.ConnectHandshakeResponse
import ai.runanywhere.proto.v1.ConnectHeartbeatRequest
import ai.runanywhere.proto.v1.ConnectHostFrame
import ai.runanywhere.proto.v1.ConnectInvocationRequest
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.types.RALLMStreamEvent
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean

internal data class AndroidConnectEndpoint(
    val id: String,
    val displayName: String,
    val address: InetSocketAddress,
)

/** Android NSD adapter for the Bonjour service published by a Connect host. */
internal class AndroidConnectDiscovery(
    context: Context,
    private val onEndpointsChanged: (List<AndroidConnectEndpoint>) -> Unit,
    private val onFailure: (Throwable) -> Unit,
) {
    private val nsdManager = context.applicationContext.getSystemService(NsdManager::class.java)
    private val lock = Any()
    private val endpoints = mutableMapOf<String, AndroidConnectEndpoint>()
    private val resolving = mutableSetOf<String>()
    private var listener: NsdManager.DiscoveryListener? = null

    fun start() {
        synchronized(lock) {
            if (listener != null) return
            val candidate = discoveryListener()
            listener = candidate
            try {
                nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, candidate)
            } catch (error: Throwable) {
                listener = null
                throw error
            }
        }
    }

    fun stop() {
        val current =
            synchronized(lock) {
                val value = listener
                listener = null
                endpoints.clear()
                resolving.clear()
                value
            }
        if (current != null) {
            runCatching { nsdManager.stopServiceDiscovery(current) }
        }
        onEndpointsChanged(emptyList())
    }

    private fun discoveryListener() =
        object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (!serviceInfo.serviceType.normalizedServiceType().startsWith(SERVICE_TYPE_BASE)) return
                resolve(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                synchronized(lock) {
                    endpoints.remove(serviceInfo.serviceName)
                    resolving.remove(serviceInfo.serviceName)
                    publishLocked()
                }
            }

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                synchronized(lock) { listener = null }
                onFailure(SDKException.networkError("Unable to search the local network (NSD $errorCode)"))
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                synchronized(lock) { listener = null }
                onFailure(SDKException.networkError("Unable to stop local-network discovery (NSD $errorCode)"))
            }
        }

    @Suppress("DEPRECATION")
    private fun resolve(serviceInfo: NsdServiceInfo) {
        val id = serviceInfo.serviceName
        synchronized(lock) {
            if (!resolving.add(id)) return
        }
        nsdManager.resolveService(
            serviceInfo,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    synchronized(lock) { resolving.remove(id) }
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    val host = serviceInfo.host
                    val port = serviceInfo.port
                    synchronized(lock) {
                        resolving.remove(id)
                        if (host != null && port in 1..65535) {
                            endpoints[id] =
                                AndroidConnectEndpoint(
                                    id = id,
                                    displayName = serviceInfo.serviceName,
                                    address = InetSocketAddress(host, port),
                                )
                            publishLocked()
                        }
                    }
                }
            },
        )
    }

    private fun publishLocked() {
        onEndpointsChanged(
            endpoints.values.sortedBy { it.displayName.lowercase() },
        )
    }

    private fun String.normalizedServiceType(): String = trim().trimEnd('.').lowercase()

    internal companion object {
        const val SERVICE_TYPE_BASE = "_runanywhere-connect._tcp"
        const val SERVICE_TYPE = "$SERVICE_TYPE_BASE."
    }
}

/** One framed TCP connection to the host selected by the Android client. */
internal class AndroidConnectSocket(
    private val scope: CoroutineScope,
    private val onDisconnected: (Throwable) -> Unit,
) {
    private val operationMutex = Mutex()
    private val disconnected = AtomicBoolean(true)
    private var socket: Socket? = null
    private var input: DataInputStream? = null
    private var output: DataOutputStream? = null
    private var heartbeatJob: Job? = null

    suspend fun connect(
        endpoint: AndroidConnectEndpoint,
        hello: ConnectClientHello,
    ): ConnectHandshakeResponse =
        withContext(Dispatchers.IO) {
            close(notify = false)
            val candidate = Socket()
            try {
                candidate.connect(endpoint.address, CONNECT_TIMEOUT_MS)
                candidate.soTimeout = HANDSHAKE_TIMEOUT_MS
                candidate.tcpNoDelay = true
                val candidateInput = DataInputStream(BufferedInputStream(candidate.getInputStream()))
                val candidateOutput = DataOutputStream(BufferedOutputStream(candidate.getOutputStream()))
                socket = candidate
                input = candidateInput
                output = candidateOutput
                disconnected.set(false)
                writeFrame(ConnectClientHello.ADAPTER.encode(hello))
                val response = ConnectHandshakeResponse.ADAPTER.decode(readFrame())
                candidate.soTimeout = 0
                response
            } catch (error: Throwable) {
                runCatching { candidate.close() }
                socket = null
                input = null
                output = null
                disconnected.set(true)
                throw mapNetworkError("Unable to connect to ${endpoint.displayName}", error)
            }
        }

    fun startHeartbeat(sessionId: String) {
        heartbeatJob?.cancel()
        heartbeatJob =
            scope.launch(Dispatchers.IO) {
                var sequence = 0L
                while (isActive && !disconnected.get()) {
                    delay(HEARTBEAT_INTERVAL_MS)
                    if (!operationMutex.tryLock()) continue
                    try {
                        sequence += 1
                        val activeSocket = requireSocket()
                        activeSocket.soTimeout = HEARTBEAT_TIMEOUT_MS
                        writeFrame(
                            ConnectClientFrame.ADAPTER.encode(
                                ConnectClientFrame(
                                    heartbeat =
                                        ConnectHeartbeatRequest(
                                            session_id = sessionId,
                                            sequence = sequence,
                                        ),
                                ),
                            ),
                        )
                        val frame = ConnectHostFrame.ADAPTER.decode(readFrame())
                        val response = frame.heartbeat
                        if (response?.session_id != sessionId || response.sequence != sequence) {
                            throw SDKException.networkError("The Connect host returned an invalid heartbeat")
                        }
                        activeSocket.soTimeout = 0
                    } catch (error: Throwable) {
                        if (error !is CancellationException) {
                            close(
                                notify = true,
                                reason =
                                    if (error is SocketTimeoutException) {
                                        SDKException.timeout(
                                            "The host stopped responding. It may have stopped or left the network.",
                                            error,
                                        )
                                    } else {
                                        mapNetworkError("The connection to the host ended", error)
                                    },
                            )
                        }
                        return@launch
                    } finally {
                        operationMutex.unlock()
                    }
                }
            }
    }

    fun generate(invocation: ConnectInvocationRequest): Flow<RALLMStreamEvent> =
        flow {
            operationMutex.lock()
            try {
                requireSocket().soTimeout = 0
                writeFrame(
                    ConnectClientFrame.ADAPTER.encode(
                        ConnectClientFrame(invocation = invocation),
                    ),
                )
                while (true) {
                    val frame = ConnectHostFrame.ADAPTER.decode(readFrame())
                    val envelope =
                        frame.invocation_event
                            ?: throw SDKException.networkError("The Connect host returned an invalid response")
                    if (envelope.request_id != invocation.request_id || envelope.event == null) {
                        throw SDKException.networkError("The Connect host returned a response for another request")
                    }
                    emit(envelope.event)
                    if (envelope.event.is_final) break
                }
            } catch (error: CancellationException) {
                // A partially consumed framed stream cannot be reused safely.
                close(notify = true, reason = error)
                throw error
            } catch (error: Throwable) {
                val mapped = mapNetworkError("Generation through the host failed", error)
                close(notify = true, reason = mapped)
                throw mapped
            } finally {
                operationMutex.unlock()
            }
        }

    fun close(
        notify: Boolean = false,
        reason: Throwable = SDKException.networkError("The connection to the host ended"),
    ) {
        heartbeatJob?.cancel()
        heartbeatJob = null
        val hadConnection = !disconnected.getAndSet(true)
        val current = socket
        socket = null
        input = null
        output = null
        runCatching { current?.close() }
        if (notify && hadConnection) onDisconnected(reason)
    }

    private fun requireSocket(): Socket =
        socket?.takeUnless { it.isClosed }
            ?: throw SDKException.networkError("The selected host is no longer connected")

    private fun writeFrame(payload: ByteArray) {
        require(payload.isNotEmpty() && payload.size <= MAXIMUM_FRAME_LENGTH) {
            "Connect frame size is invalid"
        }
        val stream = output ?: throw EOFException("Connect output stream is closed")
        stream.writeInt(payload.size)
        stream.write(payload)
        stream.flush()
    }

    private fun readFrame(): ByteArray {
        val stream = input ?: throw EOFException("Connect input stream is closed")
        val length = stream.readInt()
        if (length !in 1..MAXIMUM_FRAME_LENGTH) {
            throw SDKException.networkError("The Connect host returned an invalid frame size")
        }
        return ByteArray(length).also(stream::readFully)
    }

    private fun mapNetworkError(message: String, error: Throwable): Throwable =
        when (error) {
            is SDKException -> error
            is SocketTimeoutException -> SDKException.timeout(message, error)
            else -> SDKException.networkError("$message: ${error.message ?: "network error"}", error)
        }

    private companion object {
        const val MAXIMUM_FRAME_LENGTH = 4 * 1024 * 1024
        const val CONNECT_TIMEOUT_MS = 5_000
        const val HANDSHAKE_TIMEOUT_MS = 5_000
        const val HEARTBEAT_INTERVAL_MS = 3_000L
        const val HEARTBEAT_TIMEOUT_MS = 2_000
    }
}

/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ModelAssignment extension for CppBridge.
 * Provides model assignment callbacks for C++ core.
 *
 * Follows iOS CppBridge+ModelAssignment.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

/**
 * Model assignment bridge that provides runtime model selection callbacks for C++ core.
 *
 * The C++ core needs model assignment functionality for:
 * - Assigning models to specific component types (LLM, STT, TTS, VAD)
 * - Querying which model is currently assigned to a component
 * - Tracking assignment status and validity
 * - Managing default model assignments per component
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgeModelRegistry] and [CppBridgeModelPaths] are registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 */
object CppBridgeModelAssignment {
    /**
     * Assignment status constants matching C++ RAC_ASSIGNMENT_STATUS_* values.
     */
    object AssignmentStatus {
        /** No model assigned */
        const val NOT_ASSIGNED = 0

        /** Model is assigned but not validated */
        const val PENDING = 1

        /** Model is assigned and ready for use */
        const val READY = 2

        /** Model assignment is loading */
        const val LOADING = 3

        /** Model assignment failed (model not found, invalid, etc.) */
        const val FAILED = 4

        /** Model assignment is unloading */
        const val UNLOADING = 5

        /**
         * Get a human-readable name for the assignment status.
         */
        fun getName(status: Int): String =
            when (status) {
                NOT_ASSIGNED -> "NOT_ASSIGNED"
                PENDING -> "PENDING"
                READY -> "READY"
                LOADING -> "LOADING"
                FAILED -> "FAILED"
                UNLOADING -> "UNLOADING"
                else -> "UNKNOWN($status)"
            }

        /**
         * Check if the assignment status indicates the model is usable.
         */
        fun isUsable(status: Int): Boolean = status == READY
    }

    /**
     * Assignment failure reason constants matching C++ RAC_ASSIGNMENT_FAILURE_* values.
     */
    object FailureReason {
        /** No failure */
        const val NONE = 0

        /** Model not found in registry */
        const val MODEL_NOT_FOUND = 1

        /** Model file not found on disk */
        const val FILE_NOT_FOUND = 2

        /** Model file is corrupted or invalid */
        const val MODEL_CORRUPTED = 3

        /** Model format not supported for component */
        const val FORMAT_NOT_SUPPORTED = 4

        /** Model type does not match component type */
        const val TYPE_MISMATCH = 5

        /** Not enough memory to load model */
        const val INSUFFICIENT_MEMORY = 6

        /** Model loading failed */
        const val LOAD_FAILED = 7

        /** Unknown failure */
        const val UNKNOWN = 99

        /**
         * Get a human-readable name for the failure reason.
         */
        fun getName(reason: Int): String =
            when (reason) {
                NONE -> "NONE"
                MODEL_NOT_FOUND -> "MODEL_NOT_FOUND"
                FILE_NOT_FOUND -> "FILE_NOT_FOUND"
                MODEL_CORRUPTED -> "MODEL_CORRUPTED"
                FORMAT_NOT_SUPPORTED -> "FORMAT_NOT_SUPPORTED"
                TYPE_MISMATCH -> "TYPE_MISMATCH"
                INSUFFICIENT_MEMORY -> "INSUFFICIENT_MEMORY"
                LOAD_FAILED -> "LOAD_FAILED"
                UNKNOWN -> "UNKNOWN"
                else -> "UNKNOWN($reason)"
            }
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Model assignments by component type.
     * Key: Component type from [CppBridgeModelRegistry.ModelType]
     * Value: [ModelAssignment] data
     */
    private val assignments = mutableMapOf<Int, ModelAssignment>()

    /**
     * Default model assignments by component type.
     * Used when no explicit assignment is set.
     */
    private val defaultAssignments = mutableMapOf<Int, String>()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeModelAssignment"

    /**
     * Optional listener for model assignment events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var assignmentListener: ModelAssignmentListener? = null

    /**
     * Optional provider for custom assignment validation logic.
     * Set this to implement custom model compatibility checks.
     */
    @Volatile
    var assignmentProvider: ModelAssignmentProvider? = null

    /**
     * Model assignment data class.
     *
     * @param componentType The component type this assignment is for
     * @param modelId The assigned model ID
     * @param status The current assignment status
     * @param failureReason Failure reason if status is FAILED
     * @param assignedAt Timestamp when the assignment was made
     * @param loadedAt Timestamp when the model was loaded (if status is READY)
     */
    data class ModelAssignment(
        val componentType: Int,
        val modelId: String,
        val status: Int,
        val failureReason: Int = FailureReason.NONE,
        val assignedAt: Long = System.currentTimeMillis(),
        val loadedAt: Long = 0,
    ) {
        /**
         * Check if the assignment is ready for use.
         */
        fun isReady(): Boolean = AssignmentStatus.isUsable(status)

        /**
         * Get the component type name.
         */
        fun getComponentTypeName(): String = CppBridgeModelRegistry.ModelType.getName(componentType)

        /**
         * Get the status name.
         */
        fun getStatusName(): String = AssignmentStatus.getName(status)

        /**
         * Get the failure reason name.
         */
        fun getFailureReasonName(): String = FailureReason.getName(failureReason)
    }

    /**
     * Listener interface for model assignment events.
     */
    interface ModelAssignmentListener {
        /**
         * Called when a model is assigned to a component.
         *
         * @param componentType The component type (see [CppBridgeModelRegistry.ModelType])
         * @param modelId The assigned model ID
         */
        fun onModelAssigned(componentType: Int, modelId: String)

        /**
         * Called when a model assignment is removed.
         *
         * @param componentType The component type
         * @param previousModelId The previously assigned model ID
         */
        fun onModelUnassigned(componentType: Int, previousModelId: String)

        /**
         * Called when an assignment status changes.
         *
         * @param componentType The component type
         * @param modelId The model ID
         * @param previousStatus The previous status
         * @param newStatus The new status
         */
        fun onAssignmentStatusChanged(
            componentType: Int,
            modelId: String,
            previousStatus: Int,
            newStatus: Int,
        )

        /**
         * Called when a model assignment fails.
         *
         * @param componentType The component type
         * @param modelId The model ID
         * @param reason The failure reason (see [FailureReason])
         */
        fun onAssignmentFailed(componentType: Int, modelId: String, reason: Int)

        /**
         * Called when a model becomes ready for use.
         *
         * @param componentType The component type
         * @param modelId The model ID
         */
        fun onModelReady(componentType: Int, modelId: String)
    }

    /**
     * Provider interface for custom assignment validation logic.
     */
    interface ModelAssignmentProvider {
        /**
         * Validate if a model can be assigned to a component type.
         *
         * @param modelId The model ID to validate
         * @param componentType The component type
         * @return true if the model can be assigned, false otherwise
         */
        fun validateAssignment(modelId: String, componentType: Int): Boolean

        /**
         * Get the best model for a component type.
         *
         * This is used to auto-select a model when no explicit assignment exists.
         *
         * @param componentType The component type
         * @return The best model ID, or null if no suitable model is found
         */
        fun getBestModel(componentType: Int): String?

        /**
         * Check model compatibility with component requirements.
         *
         * @param modelId The model ID
         * @param componentType The component type
         * @return A [FailureReason] constant, or [FailureReason.NONE] if compatible
         */
        fun checkCompatibility(modelId: String, componentType: Int): Int
    }

    /**
     * Callback object for C++ model assignment API.
     * Methods are called from JNI.
     */
    private val nativeCallbackHandler = object {
        /**
         * HTTP GET callback for model assignments.
         * @param endpoint API endpoint path (e.g., "/api/v1/model-assignments/for-sdk")
         * @param requiresAuth Whether auth header is required
         * @return JSON response or "ERROR:message" on failure
         */
        @Suppress("unused") // Called from JNI
        fun httpGet(endpoint: String, requiresAuth: Boolean): String {
            return try {
                // Get base URL from telemetry config or use default
                val baseUrl = CppBridgeTelemetry.getBaseUrl()
                    ?: "https://api.runanywhere.ai"
                val fullUrl = "$baseUrl$endpoint"

                // Build headers
                val headers = mutableMapOf<String, String>()
                headers["Accept"] = "application/json"
                headers["Content-Type"] = "application/json"

                if (requiresAuth) {
                    // Get access token from auth manager
                    val accessToken = CppBridgeAuth.getValidToken()
                    if (!accessToken.isNullOrEmpty()) {
                        headers["Authorization"] = "Bearer $accessToken"
                    }
                }

                // Make HTTP request
                val response = CppBridgeHTTP.get(fullUrl, headers)

                if (response.success && response.body != null) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.DEBUG,
                        TAG,
                        "Model assignments fetched successfully",
                    )
                    response.body
                } else {
                    val errorMsg = response.errorMessage ?: "HTTP ${response.statusCode}"
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "HTTP GET failed: $errorMsg",
                    )
                    "ERROR:$errorMsg"
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "HTTP GET exception: ${e.message}",
                )
                "ERROR:${e.message}"
            }
        }
    }

    /**
     * Register the model assignment callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgeModelRegistry.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     *
     * @param autoFetch Whether to auto-fetch models after registration.
     *                  Should be false for development mode, true for staging/production.
     */
    fun register(autoFetch: Boolean = false) {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Register the model assignment callbacks with C++ via JNI
            // auto_fetch controls whether models are fetched immediately after registration
            try {
                val result = com.runanywhere.sdk.native.bridge.RunAnywhereBridge
                    .racModelAssignmentSetCallbacks(nativeCallbackHandler, autoFetch)

                if (result == 0) { // RAC_SUCCESS
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.INFO,
                        TAG,
                        "Model assignment callbacks registered (autoFetch: $autoFetch)",
                    )
                } else {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "Failed to register model assignment callbacks: $result",
                    )
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Exception registering model assignment callbacks: ${e.message}",
                )
            }

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model assignment callbacks registered",
            )
        }
    }

    /**
     * Check if the model assignment callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // MODEL ASSIGNMENT CALLBACKS
    // ========================================================================

    /**
     * Assign model callback.
     *
     * Assigns a model to a component type.
     *
     * @param componentType The component type (see [CppBridgeModelRegistry.ModelType])
     * @param modelId The model ID to assign
     * @return true if assigned successfully, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun assignModelCallback(componentType: Int, modelId: String): Boolean {
        return try {
            // Validate assignment if provider is available
            val provider = assignmentProvider
            if (provider != null) {
                val compatibilityReason = provider.checkCompatibility(modelId, componentType)
                if (compatibilityReason != FailureReason.NONE) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.WARN,
                        TAG,
                        "Model assignment failed compatibility check: ${FailureReason.getName(compatibilityReason)}",
                    )

                    // Create failed assignment
                    synchronized(lock) {
                        assignments[componentType] =
                            ModelAssignment(
                                componentType = componentType,
                                modelId = modelId,
                                status = AssignmentStatus.FAILED,
                                failureReason = compatibilityReason,
                            )
                    }

                    try {
                        assignmentListener?.onAssignmentFailed(componentType, modelId, compatibilityReason)
                    } catch (e: Exception) {
                        // Ignore listener errors
                    }

                    return false
                }
            }

            val previousAssignment: ModelAssignment?

            synchronized(lock) {
                previousAssignment = assignments[componentType]
                assignments[componentType] =
                    ModelAssignment(
                        componentType = componentType,
                        modelId = modelId,
                        status = AssignmentStatus.PENDING,
                    )
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model assigned: ${CppBridgeModelRegistry.ModelType.getName(componentType)} -> $modelId",
            )

            // Notify listener
            try {
                if (previousAssignment != null && previousAssignment.modelId != modelId) {
                    assignmentListener?.onModelUnassigned(componentType, previousAssignment.modelId)
                }
                assignmentListener?.onModelAssigned(componentType, modelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in assignment listener: ${e.message}",
                )
            }

            true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to assign model: ${e.message}",
            )
            false
        }
    }

    /**
     * Unassign model callback.
     *
     * Removes the model assignment for a component type.
     *
     * @param componentType The component type
     * @return true if unassigned, false if no assignment existed
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun unassignModelCallback(componentType: Int): Boolean {
        val removed =
            synchronized(lock) {
                assignments.remove(componentType)
            }

        if (removed != null) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Model unassigned: ${CppBridgeModelRegistry.ModelType.getName(componentType)}",
            )

            // Notify listener
            try {
                assignmentListener?.onModelUnassigned(componentType, removed.modelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in assignment listener onModelUnassigned: ${e.message}",
                )
            }

            return true
        }

        return false
    }

    /**
     * Get assigned model callback.
     *
     * Returns the model ID assigned to a component type.
     *
     * @param componentType The component type
     * @return The assigned model ID, or null if none assigned
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAssignedModelCallback(componentType: Int): String? {
        val assignment =
            synchronized(lock) {
                assignments[componentType]
            }

        if (assignment != null) {
            return assignment.modelId
        }

        // Check for default assignment
        val defaultModelId =
            synchronized(lock) {
                defaultAssignments[componentType]
            }

        if (defaultModelId != null) {
            return defaultModelId
        }

        // Try to get best model from provider
        val provider = assignmentProvider
        if (provider != null) {
            try {
                return provider.getBestModel(componentType)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error getting best model: ${e.message}",
                )
            }
        }

        return null
    }

    /**
     * Get assignment status callback.
     *
     * Returns the assignment status for a component type.
     *
     * @param componentType The component type
     * @return The assignment status (see [AssignmentStatus])
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAssignmentStatusCallback(componentType: Int): Int {
        return synchronized(lock) {
            assignments[componentType]?.status ?: AssignmentStatus.NOT_ASSIGNED
        }
    }

    /**
     * Set assignment status callback.
     *
     * Updates the assignment status for a component type.
     *
     * @param componentType The component type
     * @param status The new status (see [AssignmentStatus])
     * @param failureReason Failure reason if status is FAILED
     * @return true if updated, false if no assignment exists
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setAssignmentStatusCallback(componentType: Int, status: Int, failureReason: Int): Boolean {
        val previousStatus: Int
        val modelId: String
        val updated: Boolean

        synchronized(lock) {
            val assignment = assignments[componentType]
            if (assignment == null) {
                return false
            }

            previousStatus = assignment.status
            modelId = assignment.modelId

            if (previousStatus == status) {
                return true // No change needed
            }

            val loadedAt = if (status == AssignmentStatus.READY) System.currentTimeMillis() else assignment.loadedAt

            assignments[componentType] =
                assignment.copy(
                    status = status,
                    failureReason = if (status == AssignmentStatus.FAILED) failureReason else FailureReason.NONE,
                    loadedAt = loadedAt,
                )
            updated = true
        }

        if (updated) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Assignment status updated: ${CppBridgeModelRegistry.ModelType.getName(componentType)} " +
                    "${AssignmentStatus.getName(previousStatus)} -> ${AssignmentStatus.getName(status)}",
            )

            // Notify listener
            try {
                assignmentListener?.onAssignmentStatusChanged(componentType, modelId, previousStatus, status)

                when (status) {
                    AssignmentStatus.READY -> {
                        assignmentListener?.onModelReady(componentType, modelId)
                    }
                    AssignmentStatus.FAILED -> {
                        assignmentListener?.onAssignmentFailed(componentType, modelId, failureReason)
                    }
                }
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in assignment listener: ${e.message}",
                )
            }
        }

        return true
    }

    /**
     * Check if assignment is ready callback.
     *
     * @param componentType The component type
     * @return true if a model is assigned and ready
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isAssignmentReadyCallback(componentType: Int): Boolean {
        return synchronized(lock) {
            assignments[componentType]?.isReady() ?: false
        }
    }

    /**
     * Get all assignments callback.
     *
     * Returns all current model assignments as JSON.
     *
     * @return JSON-encoded array of assignments
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getAllAssignmentsCallback(): String {
        val allAssignments =
            synchronized(lock) {
                assignments.values.toList()
            }

        return buildString {
            append("[")
            allAssignments.forEachIndexed { index, assignment ->
                if (index > 0) append(",")
                append(assignmentToJson(assignment))
            }
            append("]")
        }
    }

    /**
     * Set default model callback.
     *
     * Sets the default model for a component type.
     *
     * @param componentType The component type
     * @param modelId The default model ID
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setDefaultModelCallback(componentType: Int, modelId: String) {
        synchronized(lock) {
            defaultAssignments[componentType] = modelId
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Default model set: ${CppBridgeModelRegistry.ModelType.getName(componentType)} -> $modelId",
        )
    }

    /**
     * Get default model callback.
     *
     * Gets the default model for a component type.
     *
     * @param componentType The component type
     * @return The default model ID, or null if not set
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getDefaultModelCallback(componentType: Int): String? {
        return synchronized(lock) {
            defaultAssignments[componentType]
        }
    }

    /**
     * Clear all assignments callback.
     *
     * Removes all model assignments.
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun clearAllAssignmentsCallback() {
        val clearedAssignments =
            synchronized(lock) {
                val all = assignments.toMap()
                assignments.clear()
                all
            }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "All assignments cleared (${clearedAssignments.size} assignments)",
        )

        // Notify listener for each cleared assignment
        try {
            clearedAssignments.forEach { (componentType, assignment) ->
                assignmentListener?.onModelUnassigned(componentType, assignment.modelId)
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in assignment listener during clear: ${e.message}",
            )
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the model assignment callbacks with C++ core.
     *
     * Registers [assignModelCallback], [unassignModelCallback],
     * [getAssignedModelCallback], [getAssignmentStatusCallback], etc. with C++ core.
     * Reserved for future native callback integration.
     *
     * C API: rac_model_assignment_set_callbacks(...)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeSetModelAssignmentCallbacks()

    /**
     * Native method to unset the model assignment callbacks.
     *
     * Called during shutdown to clean up native resources.
     * Reserved for future native callback integration.
     *
     * C API: rac_model_assignment_set_callbacks(nullptr)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnsetModelAssignmentCallbacks()

    /**
     * Native method to assign a model.
     *
     * @param componentType The component type
     * @param modelId The model ID to assign
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_assignment_assign(component_type, model_id)
     */
    @JvmStatic
    external fun nativeAssign(componentType: Int, modelId: String): Int

    /**
     * Native method to unassign a model.
     *
     * @param componentType The component type
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_assignment_unassign(component_type)
     */
    @JvmStatic
    external fun nativeUnassign(componentType: Int): Int

    /**
     * Native method to get the assigned model.
     *
     * @param componentType The component type
     * @return The assigned model ID, or null
     *
     * C API: rac_model_assignment_get(component_type)
     */
    @JvmStatic
    external fun nativeGetAssigned(componentType: Int): String?

    /**
     * Native method to load the assigned model.
     *
     * @param componentType The component type
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_assignment_load(component_type)
     */
    @JvmStatic
    external fun nativeLoad(componentType: Int): Int

    /**
     * Native method to unload the assigned model.
     *
     * @param componentType The component type
     * @return 0 on success, error code on failure
     *
     * C API: rac_model_assignment_unload(component_type)
     */
    @JvmStatic
    external fun nativeUnload(componentType: Int): Int

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the model assignment callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // Clear callbacks by calling with null
            try {
                com.runanywhere.sdk.native.bridge.RunAnywhereBridge
                    .racModelAssignmentSetCallbacks(Unit, false)
            } catch (e: Exception) {
                // Ignore errors during shutdown
            }

            assignmentListener = null
            assignmentProvider = null
            assignments.clear()
            isRegistered = false
        }
    }

    // ========================================================================
    // PUBLIC FETCH API
    // ========================================================================

    /**
     * Fetch model assignments from the backend.
     *
     * This fetches models assigned to this device based on device type and platform.
     * Results are cached and saved to the model registry.
     *
     * @param forceRefresh If true, bypass cache and fetch fresh data
     * @return JSON string of model assignments, or empty array on error
     */
    fun fetchModelAssignments(forceRefresh: Boolean = false): String {
        return try {
            val result = com.runanywhere.sdk.native.bridge.RunAnywhereBridge
                .racModelAssignmentFetch(forceRefresh)
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Fetched model assignments: ${result.take(100)}...",
            )
            result
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to fetch model assignments: ${e.message}",
            )
            "[]"
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Assign a model to a component type.
     *
     * @param componentType The component type (see [CppBridgeModelRegistry.ModelType])
     * @param modelId The model ID to assign
     * @return true if assigned successfully
     */
    fun assignModel(componentType: Int, modelId: String): Boolean {
        return assignModelCallback(componentType, modelId)
    }

    /**
     * Unassign the model from a component type.
     *
     * @param componentType The component type
     * @return true if unassigned
     */
    fun unassignModel(componentType: Int): Boolean {
        return unassignModelCallback(componentType)
    }

    /**
     * Get the model assigned to a component type.
     *
     * @param componentType The component type
     * @return The assigned model ID, or null
     */
    fun getAssignedModel(componentType: Int): String? {
        return getAssignedModelCallback(componentType)
    }

    /**
     * Get the full assignment data for a component type.
     *
     * @param componentType The component type
     * @return The [ModelAssignment] data, or null
     */
    fun getAssignment(componentType: Int): ModelAssignment? {
        return synchronized(lock) {
            assignments[componentType]
        }
    }

    /**
     * Get all current assignments.
     *
     * @return Map of component type to [ModelAssignment]
     */
    fun getAllAssignments(): Map<Int, ModelAssignment> {
        return synchronized(lock) {
            assignments.toMap()
        }
    }

    /**
     * Check if a component has a ready assignment.
     *
     * @param componentType The component type
     * @return true if the component has a model assigned and ready
     */
    fun isReady(componentType: Int): Boolean {
        return isAssignmentReadyCallback(componentType)
    }

    /**
     * Set the default model for a component type.
     *
     * @param componentType The component type
     * @param modelId The default model ID
     */
    fun setDefaultModel(componentType: Int, modelId: String) {
        setDefaultModelCallback(componentType, modelId)
    }

    /**
     * Get the default model for a component type.
     *
     * @param componentType The component type
     * @return The default model ID, or null
     */
    fun getDefaultModel(componentType: Int): String? {
        return getDefaultModelCallback(componentType)
    }

    /**
     * Clear all default assignments.
     */
    fun clearDefaultAssignments() {
        synchronized(lock) {
            defaultAssignments.clear()
        }
    }

    /**
     * Clear all assignments.
     */
    fun clearAllAssignments() {
        clearAllAssignmentsCallback()
    }

    /**
     * Assign model to LLM component.
     *
     * Convenience method for assigning a model to the LLM component.
     *
     * @param modelId The model ID
     * @return true if assigned successfully
     */
    fun assignLLMModel(modelId: String): Boolean {
        return assignModel(CppBridgeModelRegistry.ModelType.LLM, modelId)
    }

    /**
     * Assign model to STT component.
     *
     * Convenience method for assigning a model to the STT component.
     *
     * @param modelId The model ID
     * @return true if assigned successfully
     */
    fun assignSTTModel(modelId: String): Boolean {
        return assignModel(CppBridgeModelRegistry.ModelType.STT, modelId)
    }

    /**
     * Assign model to TTS component.
     *
     * Convenience method for assigning a model to the TTS component.
     *
     * @param modelId The model ID
     * @return true if assigned successfully
     */
    fun assignTTSModel(modelId: String): Boolean {
        return assignModel(CppBridgeModelRegistry.ModelType.TTS, modelId)
    }

    /**
     * Assign model to VAD component.
     *
     * Convenience method for assigning a model to the VAD component.
     *
     * @param modelId The model ID
     * @return true if assigned successfully
     */
    fun assignVADModel(modelId: String): Boolean {
        return assignModel(CppBridgeModelRegistry.ModelType.VAD, modelId)
    }

    /**
     * Get the LLM model assignment.
     *
     * @return The assigned model ID, or null
     */
    fun getLLMModel(): String? {
        return getAssignedModel(CppBridgeModelRegistry.ModelType.LLM)
    }

    /**
     * Get the STT model assignment.
     *
     * @return The assigned model ID, or null
     */
    fun getSTTModel(): String? {
        return getAssignedModel(CppBridgeModelRegistry.ModelType.STT)
    }

    /**
     * Get the TTS model assignment.
     *
     * @return The assigned model ID, or null
     */
    fun getTTSModel(): String? {
        return getAssignedModel(CppBridgeModelRegistry.ModelType.TTS)
    }

    /**
     * Get the VAD model assignment.
     *
     * @return The assigned model ID, or null
     */
    fun getVADModel(): String? {
        return getAssignedModel(CppBridgeModelRegistry.ModelType.VAD)
    }

    /**
     * Convert ModelAssignment to JSON string.
     */
    private fun assignmentToJson(assignment: ModelAssignment): String {
        return buildString {
            append("{")
            append("\"component_type\":${assignment.componentType},")
            append("\"model_id\":\"${escapeJson(assignment.modelId)}\",")
            append("\"status\":${assignment.status},")
            append("\"failure_reason\":${assignment.failureReason},")
            append("\"assigned_at\":${assignment.assignedAt},")
            append("\"loaded_at\":${assignment.loadedAt}")
            append("}")
        }
    }

    /**
     * Escape special characters for JSON string.
     */
    private fun escapeJson(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}

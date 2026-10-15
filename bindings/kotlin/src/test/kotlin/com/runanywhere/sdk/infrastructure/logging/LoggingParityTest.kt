/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.infrastructure.logging

import ai.runanywhere.proto.v1.LogLevel
import ai.runanywhere.proto.v1.LoggingConfiguration
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.configureLogging
import com.runanywhere.sdk.public.extensions.setDebugMode
import com.runanywhere.sdk.public.extensions.setLogLevel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class LoggingParityTest {

    private var previousConfiguration: LoggingConfiguration? = null
    private var previousCommonsLevel: Int = 2

    @BeforeTest
    fun setUp() {
        previousConfiguration = Logging.configuration
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            previousCommonsLevel = RunAnywhereBridge.racLoggerGetMinLevel()
        }
    }

    @AfterTest
    fun tearDown() {
        previousConfiguration?.let {
            Logging.configure(it)
        }
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            RunAnywhereBridge.racLoggerSetMinLevel(previousCommonsLevel)
        }
    }

    // MARK: - Enum Mapping

    @Test
    fun `testLogLevelToRacLogLevelMapping`() {
        assertEquals(0, LogLevel.LOG_LEVEL_TRACE.toRacLogLevel())
        assertEquals(1, LogLevel.LOG_LEVEL_DEBUG.toRacLogLevel())
        assertEquals(2, LogLevel.LOG_LEVEL_INFO.toRacLogLevel())
        assertEquals(3, LogLevel.LOG_LEVEL_WARNING.toRacLogLevel())
        assertEquals(4, LogLevel.LOG_LEVEL_ERROR.toRacLogLevel())
        assertEquals(5, LogLevel.LOG_LEVEL_FATAL.toRacLogLevel())
        assertEquals(2, LogLevel.UNRECOGNIZED.toRacLogLevel())
    }

    @Test
    fun `testRacLogLevelToProtoMapping`() {
        assertEquals(LogLevel.LOG_LEVEL_TRACE, racLogLevelToProto(0))
        assertEquals(LogLevel.LOG_LEVEL_DEBUG, racLogLevelToProto(1))
        assertEquals(LogLevel.LOG_LEVEL_INFO, racLogLevelToProto(2))
        assertEquals(LogLevel.LOG_LEVEL_WARNING, racLogLevelToProto(3))
        assertEquals(LogLevel.LOG_LEVEL_ERROR, racLogLevelToProto(4))
        assertEquals(LogLevel.LOG_LEVEL_FATAL, racLogLevelToProto(5))
        assertEquals(LogLevel.LOG_LEVEL_INFO, racLogLevelToProto(999))
    }

    // MARK: - Parity & Synchronization

    @Test
    fun `testSetLogLevelUpdatesConfiguration`() {
        RunAnywhere.setLogLevel(LogLevel.LOG_LEVEL_DEBUG)
        assertEquals(LogLevel.LOG_LEVEL_DEBUG, Logging.configuration.min_log_level)
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            assertEquals(1, RunAnywhereBridge.racLoggerGetMinLevel())
        }

        RunAnywhere.setLogLevel(LogLevel.LOG_LEVEL_ERROR)
        assertEquals(LogLevel.LOG_LEVEL_ERROR, Logging.configuration.min_log_level)
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            assertEquals(4, RunAnywhereBridge.racLoggerGetMinLevel())
        }

        RunAnywhere.setLogLevel(LogLevel.LOG_LEVEL_INFO)
        assertEquals(LogLevel.LOG_LEVEL_INFO, Logging.configuration.min_log_level)
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            assertEquals(2, RunAnywhereBridge.racLoggerGetMinLevel())
        }
    }

    @Test
    fun `testSetDebugModeUpdatesConfiguration`() {
        RunAnywhere.setDebugMode(true)
        assertEquals(LogLevel.LOG_LEVEL_DEBUG, Logging.configuration.min_log_level)
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            assertEquals(1, RunAnywhereBridge.racLoggerGetMinLevel())
        }

        RunAnywhere.setDebugMode(false)
        assertEquals(LogLevel.LOG_LEVEL_INFO, Logging.configuration.min_log_level)
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            assertEquals(2, RunAnywhereBridge.racLoggerGetMinLevel())
        }
    }

    @Test
    fun `testConfigureLoggingUpdatesConfiguration`() {
        val config = LoggingConfiguration(
            min_log_level = LogLevel.LOG_LEVEL_WARNING,
            enable_local_logging = true,
        )
        RunAnywhere.configureLogging(config)
        assertEquals(LogLevel.LOG_LEVEL_WARNING, Logging.configuration.min_log_level)
        if (RunAnywhereBridge.isNativeLibraryLoaded()) {
            assertEquals(3, RunAnywhereBridge.racLoggerGetMinLevel())
        }
    }
}

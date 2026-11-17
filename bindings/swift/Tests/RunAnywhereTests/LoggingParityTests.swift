//
//  LoggingParityTests.swift
//  RunAnywhere SDK
//
//  Coverage for log level mapping and synchronization between the
//  Swift SDK and the C++ commons logger (rac_logger).
//

import CRACommons
import Foundation
import XCTest

@testable import RunAnywhere

final class LoggingParityTests: XCTestCase {

    private var previousConfiguration: RALoggingConfiguration?
    private var previousCommonsLevel: rac_log_level_t = RAC_LOG_INFO

    override func setUp() {
        super.setUp()
        previousConfiguration = Logging.shared.configuration
        previousCommonsLevel = rac_logger_get_min_level()
    }

    override func tearDown() {
        if let previousConfiguration {
            Logging.shared.configure(previousConfiguration)
        }
        rac_logger_set_min_level(previousCommonsLevel)
        super.tearDown()
    }

    // MARK: - Enum Mapping

    func testRALogLevelToRacLogLevelMapping() {
        XCTAssertEqual(RALogLevel.trace.racLogLevel, RAC_LOG_TRACE)
        XCTAssertEqual(RALogLevel.debug.racLogLevel, RAC_LOG_DEBUG)
        XCTAssertEqual(RALogLevel.info.racLogLevel, RAC_LOG_INFO)
        XCTAssertEqual(RALogLevel.warning.racLogLevel, RAC_LOG_WARNING)
        XCTAssertEqual(RALogLevel.error.racLogLevel, RAC_LOG_ERROR)
        XCTAssertEqual(RALogLevel.fatal.racLogLevel, RAC_LOG_FATAL)
        XCTAssertEqual(RALogLevel.UNRECOGNIZED(999).racLogLevel, RAC_LOG_INFO)
    }

    func testRacLogLevelToRALogLevelMapping() {
        XCTAssertEqual(RAC_LOG_TRACE.raLogLevel, .trace)
        XCTAssertEqual(RAC_LOG_DEBUG.raLogLevel, .debug)
        XCTAssertEqual(RAC_LOG_INFO.raLogLevel, .info)
        XCTAssertEqual(RAC_LOG_WARNING.raLogLevel, .warning)
        XCTAssertEqual(RAC_LOG_ERROR.raLogLevel, .error)
        XCTAssertEqual(RAC_LOG_FATAL.raLogLevel, .fatal)
    }

    // MARK: - Parity & Synchronization

    func testSetLogLevelUpdatesCommonsMinLevel() {
        RunAnywhere.setLogLevel(.debug)
        XCTAssertEqual(rac_logger_get_min_level(), RAC_LOG_DEBUG)
        XCTAssertEqual(Logging.shared.configuration.minLogLevel, .debug)

        RunAnywhere.setLogLevel(.error)
        XCTAssertEqual(rac_logger_get_min_level(), RAC_LOG_ERROR)
        XCTAssertEqual(Logging.shared.configuration.minLogLevel, .error)

        RunAnywhere.setLogLevel(.info)
        XCTAssertEqual(rac_logger_get_min_level(), RAC_LOG_INFO)
        XCTAssertEqual(Logging.shared.configuration.minLogLevel, .info)
    }

    func testSetDebugModeUpdatesCommonsMinLevel() {
        RunAnywhere.setDebugMode(true)
        XCTAssertEqual(rac_logger_get_min_level(), RAC_LOG_DEBUG)
        XCTAssertEqual(Logging.shared.configuration.minLogLevel, .debug)

        RunAnywhere.setDebugMode(false)
        XCTAssertEqual(rac_logger_get_min_level(), RAC_LOG_INFO)
        XCTAssertEqual(Logging.shared.configuration.minLogLevel, .info)
    }

    func testConfigureLoggingUpdatesCommonsMinLevel() {
        var config = RALoggingConfiguration()
        config.minLogLevel = .warning
        RunAnywhere.configureLogging(config)
        XCTAssertEqual(rac_logger_get_min_level(), RAC_LOG_WARNING)
        XCTAssertEqual(Logging.shared.configuration.minLogLevel, .warning)

        RunAnywhere.configureLogging(.production)
        XCTAssertEqual(rac_logger_get_min_level(), RALoggingConfiguration.production.minLogLevel.racLogLevel)
        XCTAssertEqual(Logging.shared.configuration.minLogLevel, RALoggingConfiguration.production.minLogLevel)
    }
}

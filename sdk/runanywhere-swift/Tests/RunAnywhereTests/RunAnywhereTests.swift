import XCTest
@testable import RunAnywhereSDK

final class RunAnywhereSDKTests: XCTestCase {
    
    func testSDKInitialization() async throws {
        // Test that we can create a configuration
        let config = Configuration(apiKey: "test-api-key")
        
        XCTAssertEqual(config.apiKey, "test-api-key")
        XCTAssertEqual(config.baseURL.absoluteString, "https://api.runanywhere.ai")
        XCTAssertTrue(config.enableRealTimeDashboard)
        XCTAssertEqual(config.routingPolicy, .automatic)
        XCTAssertEqual(config.telemetryConsent, .granted)
    }
    
    func testGenerationOptions() throws {
        // Test generation options with default values
        let options = GenerationOptions()
        
        XCTAssertEqual(options.maxTokens, 100)
        XCTAssertEqual(options.temperature, 0.7)
        XCTAssertEqual(options.topP, 1.0)
        XCTAssertTrue(options.enableRealTimeTracking)
        XCTAssertNil(options.context)
        XCTAssertTrue(options.stopSequences.isEmpty)
        XCTAssertNil(options.seed)
    }
    
    func testSDKSingleton() {
        // Test that SDK is a singleton
        let sdk1 = RunAnywhereSDK.shared
        let sdk2 = RunAnywhereSDK.shared
        
        XCTAssertTrue(sdk1 === sdk2)
    }
    
    func testSDKNotInitializedError() async {
        // Test that SDK throws error when not initialized
        do {
            _ = try await RunAnywhereSDK.shared.generate("test prompt")
            XCTFail("Should throw notInitialized error")
        } catch let error as SDKError {
            if case .notInitialized = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

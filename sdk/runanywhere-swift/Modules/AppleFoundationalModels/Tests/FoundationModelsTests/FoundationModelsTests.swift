import XCTest
@testable import FoundationModelsAdapter

final class FoundationModelsTests: XCTestCase {

    @available(iOS 26.0, macOS 26.0, *)
    func testAdapterFramework() {
        let adapter = FoundationModelsAdapter()
        XCTAssertEqual(adapter.framework, .foundationModels)
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testSupportedModalities() {
        let adapter = FoundationModelsAdapter()
        XCTAssertTrue(adapter.supportedModalities.contains(.textToText))
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testProvidedModels() {
        let adapter = FoundationModelsAdapter()
        let models = adapter.getProvidedModels()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.id, "foundation-models-default")
        XCTAssertEqual(models.first?.name, "Apple Foundation Models")
    }
}

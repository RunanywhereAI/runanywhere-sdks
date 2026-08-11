//
//  HTTPClientAdapterAuthHeaderTests.swift
//  RunAnywhere SDK
//
//  PR #605 review issue #5 — cross-SDK auth header parity.
//
//  Characterizes the split-header contract for `HTTPClientAdapter`: `apikey`
//  always travels independently of `Authorization`, and `Authorization:
//  Bearer` carries only a JWT access token — never a fallback to the API
//  key. Mirrors Kotlin's `HTTPClientAdapter.buildHeaders` / `resolveToken`
//  and the Flutter `buildAuthHeaders` / `resolveAccessToken` characterization.
//

import CRACommons
import Foundation
import XCTest

@testable import RunAnywhere

final class HTTPClientAdapterAuthHeadersTests: XCTestCase {

    func testAPIKeyOnlyProducesOnlyTheApikeyHeader() {
        let headers = HTTPClientAdapter.authHeaders(apiKey: "sk-test-key", authToken: nil)

        XCTAssertEqual(headers["apikey"], "sk-test-key")
        XCTAssertNil(headers["Authorization"])
    }

    func testJWTOnlyProducesOnlyTheAuthorizationHeader() {
        let headers = HTTPClientAdapter.authHeaders(apiKey: nil, authToken: "jwt-token")

        XCTAssertNil(headers["apikey"])
        XCTAssertEqual(headers["Authorization"], "Bearer jwt-token")
    }

    func testAPIKeyAndJWTTogetherSetBothHeadersIndependently() {
        let headers = HTTPClientAdapter.authHeaders(apiKey: "sk-test-key", authToken: "jwt-token")

        XCTAssertEqual(headers["apikey"], "sk-test-key")
        XCTAssertEqual(headers["Authorization"], "Bearer jwt-token")
    }

    func testKeylessProducesNeitherHeader() {
        let headers = HTTPClientAdapter.authHeaders(apiKey: nil, authToken: nil)

        XCTAssertTrue(headers.isEmpty)
    }

    func testEmptyStringsAreTreatedAsAbsent() {
        let headers = HTTPClientAdapter.authHeaders(apiKey: "", authToken: "")

        XCTAssertTrue(headers.isEmpty)
    }

    func testNeverFallsBackToTheAPIKeyAsABearerToken() {
        // A caller accidentally passing the API key as the access token is
        // exactly the collapsed-header regression this contract forbids —
        // this test only pins that `authHeaders` itself never derives
        // `Authorization` from `apiKey`.
        let headers = HTTPClientAdapter.authHeaders(apiKey: "sk-test-key", authToken: nil)

        XCTAssertNil(headers["Authorization"])
    }
}

final class HTTPClientAdapterResolveTokenTests: XCTestCase {

    override func tearDown() {
        _ = rac_auth_clear()
        super.tearDown()
    }

    func testRequiresAuthFalseNeverAttemptsNativeResolutionOrReturnsAFallback() async throws {
        // Even with a previous (now-cleared) auth attempt, a request that
        // does not require auth must never surface a bearer token.
        _ = rac_auth_clear()
        let adapter = HTTPClientAdapter.shared

        let token = try await adapter.resolveToken(requiresAuth: false)

        XCTAssertNil(token, "requiresAuth=false must omit Authorization entirely")
    }

    func testRequiresAuthTrueWithNoStoredCredentialOmitsAuthorizationInsteadOfFallingBack() async throws {
        // Keyless / expired-token / resolver-failure all converge on the
        // same native signal: no valid token available. The regression this
        // pins is that the adapter must not substitute the configured API
        // key as a bearer token in that case.
        _ = rac_auth_clear()
        let adapter = HTTPClientAdapter.shared

        let token = try await adapter.resolveToken(requiresAuth: true)

        XCTAssertNil(token, "no stored credential must omit Authorization, never fall back to the API key")
    }
}

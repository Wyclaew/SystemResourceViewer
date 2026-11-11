import XCTest
@testable import SystemResourceViewer

final class UpdateCheckerTests: XCTestCase {

    func testSemanticVersionStandardParsing() {
        let v = SemanticVersion(string: "1.2.3")
        XCTAssertEqual(v.major, 1)
        XCTAssertEqual(v.minor, 2)
        XCTAssertEqual(v.patch, 3)
        XCTAssertNil(v.prerelease)
    }

    func testSemanticVersionWithPrefix() {
        let vLower = SemanticVersion(string: "v2.0.1")
        XCTAssertEqual(vLower.major, 2)
        XCTAssertEqual(vLower.minor, 0)
        XCTAssertEqual(vLower.patch, 1)

        let vUpper = SemanticVersion(string: "V3.4.5")
        XCTAssertEqual(vUpper.major, 3)
        XCTAssertEqual(vUpper.minor, 4)
        XCTAssertEqual(vUpper.patch, 5)
    }

    func testSemanticVersionComparisonMinor() {
        let v1 = SemanticVersion(string: "1.1.0")
        let v2 = SemanticVersion(string: "1.2.0")
        XCTAssertTrue(v1 < v2)
        XCTAssertFalse(v2 < v1)
    }

    func testSemanticVersionComparisonMajor() {
        let v1 = SemanticVersion(string: "1.9.9")
        let v2 = SemanticVersion(string: "2.0.0")
        XCTAssertTrue(v1 < v2)
    }

    func testGitHubReleaseContractJSONDecoding() throws {
        let json = """
        {
            "tag_name": "v1.5.0",
            "name": "Version 1.5.0",
            "body": "Major performance optimizations.",
            "html_url": "https://github.com/WycDev/SystemResourceViewer/releases/tag/v1.5.0",
            "published_at": "2026-11-11T12:00:00Z"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubReleaseContract.self, from: json)
        XCTAssertEqual(release.tagName, "v1.5.0")
        XCTAssertEqual(release.name, "Version 1.5.0")
        XCTAssertEqual(release.body, "Major performance optimizations.")
        XCTAssertEqual(release.htmlUrl, "https://github.com/WycDev/SystemResourceViewer/releases/tag/v1.5.0")
        XCTAssertEqual(release.publishedAt, "2026-11-11T12:00:00Z")
    }

    func testUpdateCheckerLogicDetectsNewerVersion() {
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.0.0", remoteTag: "v1.0.1"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.0.0", remoteTag: "1.1.0"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.2.3", remoteTag: "2.0.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.0.1", remoteTag: "v1.0.0"))
    }

    // MARK: - UpdateCheckerService & ViewModel Integration Tests

    private func makeMockSession(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testUpdateCheckerServiceDetectsNewRelease() async {
        let sampleJSON = """
        {
            "tag_name": "v2.0.0",
            "name": "Version 2.0.0 Release",
            "body": "Major upgrade.",
            "html_url": "https://github.com/WycDev/SystemResourceViewer/releases/tag/v2.0.0",
            "published_at": "2026-11-11T12:00:00Z"
        }
        """.data(using: .utf8)!

        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sampleJSON)
        }

        let service = UpdateCheckerService(session: session)
        let release = await service.checkForUpdates(currentVersion: "1.0.0")

        XCTAssertNotNil(release)
        XCTAssertEqual(release?.tagName, "v2.0.0")
        XCTAssertEqual(release?.name, "Version 2.0.0 Release")
    }

    func testUpdateCheckerServiceIgnoresOlderRelease() async {
        let sampleJSON = """
        {
            "tag_name": "v1.0.0",
            "name": "Version 1.0.0",
            "body": "Initial.",
            "html_url": "https://github.com/WycDev/SystemResourceViewer/releases/tag/v1.0.0",
            "published_at": "2026-11-11T12:00:00Z"
        }
        """.data(using: .utf8)!

        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sampleJSON)
        }

        let service = UpdateCheckerService(session: session)
        let release = await service.checkForUpdates(currentVersion: "2.0.0")

        XCTAssertNil(release)
    }

    func testUpdateCheckerServiceHandlesHTTPErrorGracefully() async {
        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = UpdateCheckerService(session: session)
        let release = await service.checkForUpdates(currentVersion: "1.0.0")

        XCTAssertNil(release)
    }

    func testUpdateCheckerServiceHandlesNetworkFailureGracefully() async {
        let session = makeMockSession { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = UpdateCheckerService(session: session)
        let release = await service.checkForUpdates(currentVersion: "1.0.0")

        XCTAssertNil(release)
    }

    @MainActor
    func testDashboardViewModelUpdateFlow() async {
        let sampleJSON = """
        {
            "tag_name": "v3.0.0",
            "name": "Version 3.0.0",
            "body": "New major release.",
            "html_url": "https://github.com/WycDev/SystemResourceViewer/releases/tag/v3.0.0",
            "published_at": "2026-11-11T12:00:00Z"
        }
        """.data(using: .utf8)!

        let session = makeMockSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, sampleJSON)
        }

        let service = UpdateCheckerService(session: session)
        let vm = DashboardViewModel(interval: 10.0, updateCheckerService: service)

        XCTAssertNil(vm.pendingUpdate)
        XCTAssertFalse(vm.showUpdateConfirmation)

        await vm.checkForUpdates(currentVersion: "1.0.0")

        XCTAssertNotNil(vm.pendingUpdate)
        XCTAssertEqual(vm.pendingUpdate?.tagName, "v3.0.0")
        XCTAssertTrue(vm.showUpdateConfirmation)

        vm.dismissUpdate()

        XCTAssertNil(vm.pendingUpdate)
        XCTAssertFalse(vm.showUpdateConfirmation)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

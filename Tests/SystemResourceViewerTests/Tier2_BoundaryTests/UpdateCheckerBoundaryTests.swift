import XCTest
@testable import SystemResourceViewer

final class UpdateCheckerBoundaryTests: XCTestCase {

    func testEmptyStringSemverGracefulParsing() {
        let v = SemanticVersion(string: "")
        XCTAssertEqual(v.major, 0)
        XCTAssertEqual(v.minor, 0)
        XCTAssertEqual(v.patch, 0)
        XCTAssertNil(v.prerelease)
    }

    func testNonNumericGarbageSemverParsing() {
        let v = SemanticVersion(string: "alpha-beta-dev")
        XCTAssertEqual(v.major, 0)
        XCTAssertEqual(v.minor, 0)
        XCTAssertEqual(v.patch, 0)
    }

    func testIdenticalVersionsComparisonNoUpdate() {
        let current = "1.0.0"
        let remote = "v1.0.0"
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: current, remoteTag: remote))

        let v1 = SemanticVersion(string: current)
        let v2 = SemanticVersion(string: remote)
        XCTAssertEqual(v1, v2)
    }

    func testDowngradeRemoteVersionNoUpdate() {
        let current = "2.1.0"
        let olderRemote = "v2.0.5"
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: current, remoteTag: olderRemote))
    }

    func testPrereleaseTagComparison() {
        let release = SemanticVersion(string: "1.0.0")
        let beta = SemanticVersion(string: "1.0.0-beta.1")
        // Release version is newer than prerelease of same major/minor/patch
        XCTAssertTrue(beta < release)
        XCTAssertFalse(release < beta)
    }

    func testGitHubReleaseDecodingWithNullNameAndBody() throws {
        let json = """
        {
            "tag_name": "v2.0.0",
            "name": null,
            "body": null,
            "html_url": "https://github.com/WycDev/SystemResourceViewer/releases/tag/v2.0.0",
            "published_at": "2026-11-11T14:00:00Z"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v2.0.0")
        XCTAssertEqual(release.name, "")
        XCTAssertEqual(release.body, "")
        XCTAssertEqual(release.htmlUrl, "https://github.com/WycDev/SystemResourceViewer/releases/tag/v2.0.0")
        XCTAssertEqual(release.publishedAt, "2026-11-11T14:00:00Z")
    }

    func testGitHubReleaseDecodingWithMissingFields() throws {
        let json = """
        {
            "tag_name": "v3.0.0"
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v3.0.0")
        XCTAssertEqual(release.name, "")
        XCTAssertEqual(release.body, "")
        XCTAssertEqual(release.htmlUrl, "")
        XCTAssertEqual(release.publishedAt, "")
    }
}

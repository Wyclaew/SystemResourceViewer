import Foundation

/// Actor-isolated network service for querying GitHub Releases and detecting application updates.
public actor UpdateCheckerService: Sendable {
    public static let shared = UpdateCheckerService()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Queries the latest GitHub release for the repository and determines if an update is available.
    ///
    /// - Parameters:
    ///   - currentVersion: The current running application version (e.g. "1.0.0").
    ///   - repo: The GitHub repository identifier in "owner/repo" format. Default is "Wyclaew/SystemResourceViewer".
    /// - Returns: A `GitHubRelease` instance if a newer version is available, or `nil` if up-to-date or if any error occurs.
    public func checkForUpdates(
        currentVersion: String,
        repo: String = "Wyclaew/SystemResourceViewer"
    ) async -> GitHubRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        request.httpMethod = "GET"
        request.setValue("SystemResourceViewer", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)
            if UpdateCheckerLogic.isUpdateAvailable(current: currentVersion, remoteTag: release.tagName) {
                return release
            }
            return nil
        } catch {
            return nil
        }
    }
}

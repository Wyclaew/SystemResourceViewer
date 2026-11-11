import Foundation

/// GitHub Release metadata model matching GitHub Releases API.
public struct GitHubRelease: Codable, Sendable, Equatable {
    public let tagName: String
    public let name: String
    public let body: String
    public let htmlUrl: String
    public let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
    }

    public init(
        tagName: String,
        name: String = "",
        body: String = "",
        htmlUrl: String = "",
        publishedAt: String = ""
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlUrl = htmlUrl
        self.publishedAt = publishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tagName = try container.decode(String.self, forKey: .tagName)
        self.name = (try container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        self.body = (try container.decodeIfPresent(String.self, forKey: .body)) ?? ""
        self.htmlUrl = (try container.decodeIfPresent(String.self, forKey: .htmlUrl)) ?? ""
        self.publishedAt = (try container.decodeIfPresent(String.self, forKey: .publishedAt)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tagName, forKey: .tagName)
        try container.encode(name, forKey: .name)
        try container.encode(body, forKey: .body)
        try container.encode(htmlUrl, forKey: .htmlUrl)
        try container.encode(publishedAt, forKey: .publishedAt)
    }
}

/// Semantic Version parser and comparison matching SemVer specifications.
public struct SemanticVersion: Comparable, Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(string: String) {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        if cleaned.isEmpty {
            self.major = 0
            self.minor = 0
            self.patch = 0
            self.prerelease = nil
            return
        }

        let dashParts = cleaned.split(separator: "-", maxSplits: 1)
        let versionPart = String(dashParts[0])
        self.prerelease = dashParts.count > 1 ? String(dashParts[1]) : nil

        let parts = versionPart.split(separator: ".").compactMap { Int($0) }
        self.major = parts.count > 0 ? parts[0] : 0
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A release version is newer than a prerelease version of the same numbers (e.g. 1.0.0-beta.1 < 1.0.0)
        if lhs.prerelease != nil && rhs.prerelease == nil {
            return true
        }
        if lhs.prerelease == nil && rhs.prerelease != nil {
            return false
        }
        if let lPre = lhs.prerelease, let rPre = rhs.prerelease {
            return lPre.localizedStandardCompare(rPre) == .orderedAscending
        }
        return false
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }
}

/// Pure logic helper for comparing current version string with remote tag.
public struct UpdateCheckerLogic: Sendable {
    public static func isUpdateAvailable(current: String, remoteTag: String) -> Bool {
        let currentVer = SemanticVersion(string: current)
        let remoteVer = SemanticVersion(string: remoteTag)
        return remoteVer > currentVer
    }
}

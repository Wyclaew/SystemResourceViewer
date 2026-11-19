import Foundation

/// Strict URL validator safeguarding against malicious URI schemes, open redirects,
/// and external link manipulation before invoking system URL openers.
public enum SafeURLValidator: Sendable {

    /// Default whitelist of permitted external domains.
    public static let defaultAllowedHosts: Set<String> = [
        "github.com",
        "api.github.com"
    ]

    /// Validates a URL string ensuring strict HTTPS scheme and allowed host domain.
    ///
    /// - Parameters:
    ///   - urlString: The raw URL string to validate.
    ///   - allowedHosts: Optional set of allowed domain names. Defaults to `defaultAllowedHosts`.
    /// - Returns: A validated `URL` instance if all security criteria are met, otherwise `nil`.
    public static func validate(
        urlString: String,
        allowedHosts: Set<String> = defaultAllowedHosts
    ) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return nil
        }
        return validate(url: url, allowedHosts: allowedHosts)
    }

    /// Validates a `URL` ensuring strict HTTPS scheme and allowed host domain.
    ///
    /// - Parameters:
    ///   - url: The `URL` to inspect.
    ///   - allowedHosts: Optional set of allowed domain names. Defaults to `defaultAllowedHosts`.
    /// - Returns: The validated `URL` if valid, otherwise `nil`.
    public static func validate(
        url: URL,
        allowedHosts: Set<String> = defaultAllowedHosts
    ) -> URL? {
        // 1. Strictly enforce HTTPS scheme (rejects http, file, applescript, terminal, javascript, data, etc.)
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            return nil
        }

        // 2. Reject embedded userinfo (e.g. https://user:password@...)
        guard url.user == nil, url.password == nil else {
            return nil
        }

        // 3. Validate host against allowed domain whitelist
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }

        let isPermitted = allowedHosts.contains(host) || allowedHosts.contains { allowed in
            host.hasSuffix("." + allowed)
        }

        guard isPermitted else {
            return nil
        }

        // 4. Reject non-standard ports (HTTPS standard port is 443 or nil)
        if let port = url.port, port != 443 {
            return nil
        }

        return url
    }

    /// Convenience predicate checking whether a URL string is safe.
    public static func isValid(
        urlString: String,
        allowedHosts: Set<String> = defaultAllowedHosts
    ) -> Bool {
        validate(urlString: urlString, allowedHosts: allowedHosts) != nil
    }

    /// Convenience predicate checking whether a `URL` is safe.
    public static func isValid(
        url: URL,
        allowedHosts: Set<String> = defaultAllowedHosts
    ) -> Bool {
        validate(url: url, allowedHosts: allowedHosts) != nil
    }
}

import Foundation

/// User-configurable privacy settings governing telemetry redaction,
/// outbound network latency probes, and sensitive credential masking.
public struct PrivacySettings: Codable, Sendable, Equatable {

    /// When true, replaces API tokens, passwords, and sensitive keys in process arguments with ***REDACTED***.
    public var maskSensitiveArguments: Bool

    /// When true, allows lightweight TCP socket probes to 1.1.1.1:53 for network latency measurement.
    /// When false, completely halts all external socket probes (zero outbound telemetry).
    public var allowExternalSocketProbe: Bool

    /// When true, masks or obfuscates local IPv4 address in telemetry presentations.
    public var maskLocalIPAddress: Bool

    /// When true, hides macOS system daemons and root processes from default process list view.
    public var hideSystemProcessesByDefault: Bool

    public init(
        maskSensitiveArguments: Bool = true,
        allowExternalSocketProbe: Bool = true,
        maskLocalIPAddress: Bool = false,
        hideSystemProcessesByDefault: Bool = false
    ) {
        self.maskSensitiveArguments = maskSensitiveArguments
        self.allowExternalSocketProbe = allowExternalSocketProbe
        self.maskLocalIPAddress = maskLocalIPAddress
        self.hideSystemProcessesByDefault = hideSystemProcessesByDefault
    }

    /// Default privacy settings: sensitive masking and socket probe enabled, local IP visible.
    public static let defaultSettings = PrivacySettings()

    /// Sanitizes an array of process command-line arguments based on `maskSensitiveArguments`.
    public func sanitize(arguments: [String]) -> [String] {
        guard maskSensitiveArguments else { return arguments }
        return SensitiveDataSanitizer.sanitize(arguments: arguments)
    }

    /// Sanitizes a single argument or command line string based on `maskSensitiveArguments`.
    public func sanitize(argument: String) -> String {
        guard maskSensitiveArguments else { return argument }
        return SensitiveDataSanitizer.sanitize(argument: argument)
    }

    /// Masks an IPv4 address if `maskLocalIPAddress` is enabled.
    public func sanitize(ipv4: String) -> String {
        guard maskLocalIPAddress else { return ipv4 }
        let components = ipv4.split(separator: ".")
        if components.count == 4 {
            return "\(components[0]).\(components[1]).*.*"
        }
        return "•••.•••.•••.•••"
    }
}

/// Regular expression engine scrubbing credentials, API tokens, cloud keys,
/// and passwords from process command-line strings and telemetry logs.
public struct SensitiveDataSanitizer: Sendable {

    private struct PatternDefinition: @unchecked Sendable {
        let regex: NSRegularExpression
        let template: String
    }

    private static let patternDefinitions: [PatternDefinition] = [
        // 1. OpenAI / Anthropic / AI tokens (sk-...)
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(sk-[a-zA-Z0-9_\-]{20,})"#),
            template: "***REDACTED***"
        ),
        // 2. GitHub Personal Access Tokens (ghp_, gho_, ghu_, ghs_, ghr_)
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(gh[pousr]_[A-Za-z0-9_]{20,})"#),
            template: "***REDACTED***"
        ),
        // 3. AWS Access Key ID (AKIA...)
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(AKIA[0-9A-Z]{16})"#),
            template: "***REDACTED***"
        ),
        // 4. AWS Secret Key assignment
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(?i)((?:aws_secret_access_key|aws_secret_key)\s*[:=]\s*)([A-Za-z0-9/+=]{40})"#),
            template: "$1***REDACTED***"
        ),
        // 5. Bearer / Authorization tokens
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(?i)(bearer\s+)([a-zA-Z0-9_\-\.]{20,})"#),
            template: "$1***REDACTED***"
        ),
        // 6. CLI flags: --password=XYZ, --token=XYZ, --api-key=XYZ, --secret=XYZ, --auth=XYZ
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(?i)(--(?:password|secret|token|api[-_]?key|auth)=)(\S+)"#),
            template: "$1***REDACTED***"
        ),
        // 7. CLI short password flag: -p XYZ
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(?i)(-(?:p)\s+)(\S+)"#),
            template: "$1***REDACTED***"
        ),
        // 8. Database / URI embedded credentials: postgres://user:password@host
        PatternDefinition(
            regex: try! NSRegularExpression(pattern: #"(://[^:\s@/]+:)([^/\s]+)(@[^/@\s]+)"#),
            template: "$1***REDACTED***$3"
        )
    ]

    private static let sensitiveFlags: Set<String> = [
        "--password",
        "-p",
        "--token",
        "--api-key",
        "--api_key",
        "--apikey",
        "--secret",
        "--auth",
        "--auth-token",
        "--auth_token"
    ]

    /// Sanitizes an array of command-line arguments, scrubbing both regex patterns
    /// and multi-token flag values (e.g. `["--password", "secret"]` -> `["--password", "***REDACTED***"]`).
    public static func sanitize(arguments: [String]) -> [String] {
        var result: [String] = []
        var redactNext = false

        for arg in arguments {
            if redactNext {
                result.append("***REDACTED***")
                redactNext = false
                continue
            }

            let lower = arg.lowercased()
            if sensitiveFlags.contains(lower) {
                result.append(arg)
                redactNext = true
            } else {
                result.append(sanitize(argument: arg))
            }
        }

        return result
    }

    /// Sanitizes a single argument or full command line string.
    public static func sanitize(argument: String) -> String {
        var result = argument
        for item in patternDefinitions {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = item.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: item.template
            )
        }
        return result
    }
}

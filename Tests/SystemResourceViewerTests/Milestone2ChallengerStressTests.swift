import XCTest
@testable import SystemResourceViewer

final class Milestone2ChallengerStressTests: XCTestCase {

    // MARK: - 1. ProcessGuard Adversarial Stress Tests

    func testProcessGuardNegativeAndBoundaryPIDs() {
        let boundaryPIDs: [pid_t] = [
            0,
            1,
            -1,
            -2,
            -100,
            -9999,
            Int32.min,
            -2147483648
        ]

        for pid in boundaryPIDs {
            let isProt = ProcessGuard.isProtected(pid: pid)
            XCTAssertTrue(isProt, "PID \(pid) must be strictly protected.")
            
            let status = ProcessGuard.protectionStatus(pid: pid)
            XCTAssertTrue(status.protected, "Protection status for PID \(pid) must be true.")
            XCTAssertNotNil(status.reason, "Protection status for PID \(pid) must provide a reason.")
            XCTAssertTrue(
                status.reason?.contains("Cannot terminate system initialization process") == true,
                "Reason for PID \(pid) should mention system initialization: \(status.reason ?? "nil")"
            )
        }
    }

    func testProcessGuardSelfAndParentPIDProtection() {
        let selfPID = getpid()
        XCTAssertTrue(ProcessGuard.isProtected(pid: selfPID), "Active self PID (\(selfPID)) must be protected.")
        let selfStatus = ProcessGuard.protectionStatus(pid: selfPID)
        XCTAssertTrue(selfStatus.protected)
        XCTAssertEqual(selfStatus.reason, "Cannot terminate the active Resource Monitor application directly.")

        let ppid = getppid()
        if ppid > 1 {
            XCTAssertTrue(ProcessGuard.isProtected(pid: ppid), "Parent PID (\(ppid)) must be protected.")
            let parentStatus = ProcessGuard.protectionStatus(pid: ppid)
            XCTAssertTrue(parentStatus.protected)
            XCTAssertEqual(parentStatus.reason, "Cannot terminate parent host process (PID \(ppid)).")
        }
    }

    func testProcessGuardAllBlockedNamesWithCaseVariations() {
        let testPID: pid_t = 65432
        for blockedName in ProcessGuard.blockedProcessNames {
            let variations = [
                blockedName,
                blockedName.lowercased(),
                blockedName.uppercased()
            ]

            for variation in variations {
                XCTAssertTrue(
                    ProcessGuard.isProtected(pid: testPID, name: variation),
                    "Process variation '\(variation)' for '\(blockedName)' must be protected."
                )
            }
        }
    }

    func testProcessGuardPartialMatchesAreNotFalselyBlocked() {
        // Substrings or compound names of protected daemons should NOT be blocked if they are user processes
        let benignCompounds = [
            "PathFinder",
            "FinderHelper",
            "FinderSyncExtension",
            "DockTile",
            "MyDockApp",
            "WindowServerProxy",
            "launchdaemon_tool",
            "DiskWiper",
            "SecurityTools",
            "PowerDaemonClient"
        ]

        let dummyPID: pid_t = 77777
        for name in benignCompounds {
            let isProt = ProcessGuard.isProtected(
                pid: dummyPID,
                name: name,
                path: "/Applications/\(name).app/Contents/MacOS/\(name)"
            )
            XCTAssertFalse(
                isProt,
                "Benign compound process '\(name)' should NOT be falsely blocked by ProcessGuard."
            )
        }
    }

    func testProcessGuardBenignUserProcesses() {
        let benignApps = [
            "Safari",
            "Google Chrome",
            "Slack",
            "Visual Studio Code",
            "Xcode",
            "Terminal",
            "node",
            "python3",
            "ruby",
            "rustc",
            "swift",
            "zsh",
            "bash",
            "git"
        ]

        let dummyPID: pid_t = 55555
        for name in benignApps {
            let status = ProcessGuard.protectionStatus(
                pid: dummyPID,
                name: name,
                bundleIdentifier: "com.user.\(name.lowercased().replacingOccurrences(of: " ", with: ""))",
                path: "/usr/local/bin/\(name)"
            )
            XCTAssertFalse(status.protected, "Benign user process '\(name)' must NOT be protected.")
            XCTAssertNil(status.reason)
        }
    }

    func testProcessGuardProtectedCoreServicesPaths() {
        let protectedPaths = [
            "/System/Library/CoreServices/WindowServer",
            "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
            "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
            "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            "/usr/libexec/diskarbitrationd",
            "/usr/libexec/syspolicyd",
            "/usr/libexec/opendirectoryd"
        ]

        for path in protectedPaths {
            let isProt = ProcessGuard.isProtected(pid: 99999, path: path)
            XCTAssertTrue(isProt, "Path '\(path)' must be protected by ProcessGuard.")
        }
    }

    func testProcessActionIntegrationWithProcessGuard() {
        // 1. Guard against PID 0
        let resPID0 = ProcessAction.terminate(pid: 0)
        XCTAssertEqual(resPID0, .failure("Cannot terminate system initialization process (PID 0)."))

        let resForcePID0 = ProcessAction.forceKill(pid: 0)
        XCTAssertEqual(resForcePID0, .failure("Cannot terminate system initialization process (PID 0)."))

        // 2. Guard against PID 1
        let resPID1 = ProcessAction.terminate(pid: 1)
        XCTAssertEqual(resPID1, .failure("Cannot terminate system initialization process (PID 1)."))

        let resForcePID1 = ProcessAction.forceKill(pid: 1)
        XCTAssertEqual(resForcePID1, .failure("Cannot terminate system initialization process (PID 1)."))

        // 3. Guard against self PID
        let resSelf = ProcessAction.terminate(pid: getpid())
        XCTAssertEqual(resSelf, .failure("Cannot terminate the active Resource Monitor application directly."))

        let resForceSelf = ProcessAction.forceKill(pid: getpid())
        XCTAssertEqual(resForceSelf, .failure("Cannot terminate the active Resource Monitor application directly."))

        // 4. Guard against critical daemons by name
        let resWindowServer = ProcessAction.terminate(pid: 99998, name: "WindowServer")
        XCTAssertEqual(resWindowServer, .failure("Cannot terminate critical system process 'WindowServer' (PID 99998)."))

        let resDock = ProcessAction.forceKill(pid: 99997, name: "Dock")
        XCTAssertEqual(resDock, .failure("Cannot terminate critical system process 'Dock' (PID 99997)."))

        let resFinder = ProcessAction.terminate(pid: 99996, name: "finder")
        XCTAssertEqual(resFinder, .failure("Cannot terminate critical system process 'finder' (PID 99996)."))

        // 5. Non-existent benign PID should pass ProcessGuard and fail gracefully via POSIX ESRCH
        let benignNonExistentPID: pid_t = 99995
        let resBenign = ProcessAction.terminate(pid: benignNonExistentPID, name: "NonExistentDummyApp")
        XCTAssertEqual(
            resBenign,
            .failure("No such process (ESRCH). Process \(benignNonExistentPID) has already terminated.")
        )
    }

    // MARK: - 2. SafeURLValidator Adversarial Stress Tests

    func testSafeURLValidatorRejectsAllNonHttpsSchemes() {
        let badSchemes = [
            "http://github.com/WycDev/SystemResourceViewer",
            "HTTP://GITHUB.COM/WycDev/SystemResourceViewer",
            "file:///etc/passwd",
            "file:///Applications/Utilities/Terminal.app",
            "applescript://com.apple.ScriptEditor?cmd=beep",
            "terminal://echo%20pwned",
            "javascript:alert(1)",
            "javascript://github.com/%0Aalert(1)",
            "data:text/html,<script>alert(1)</script>",
            "data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==",
            "vbscript:msgbox(1)",
            "about:blank",
            "blob:https://github.com/d3b07384-d113-49d7-83d5-a3d8b34c0e66",
            "ws://github.com/socket",
            "wss://github.com/socket",
            "ssh://git@github.com",
            "telnet://github.com:23",
            "ftp://github.com/archive.zip",
            "ldap://github.com/dc=example"
        ]

        for urlString in badSchemes {
            let validated = SafeURLValidator.validate(urlString: urlString)
            XCTAssertNil(validated, "Non-HTTPS or dangerous scheme MUST be rejected: \(urlString)")
            XCTAssertFalse(SafeURLValidator.isValid(urlString: urlString))
        }
    }

    func testSafeURLValidatorRejectsUserinfoInjection() {
        let userinfoPayloads = [
            "https://attacker@github.com/releases",
            "https://attacker:secret@github.com/releases",
            "https://user:password@github.com",
            "https://admin@api.github.com/v1",
            "https://user:pass@github.com:443"
        ]

        for urlString in userinfoPayloads {
            let validated = SafeURLValidator.validate(urlString: urlString)
            XCTAssertNil(validated, "Userinfo injection MUST be rejected: \(urlString)")
            XCTAssertFalse(SafeURLValidator.isValid(urlString: urlString))
        }
    }

    func testSafeURLValidatorRejectsHostSpoofingAndBypasses() {
        let spoofingPayloads = [
            "https://github.com.evil.com/releases",
            "https://github.com@evil.com/releases",
            "https://evil-github.com/releases",
            "https://fakegithub.com/releases",
            "https://attacker.com/?https://github.com",
            "https://attacker.com#github.com",
            "https://notgithub.com",
            "https://github.com.attacker.org",
            "https://raw.githubusercontent.com/test", // not in default whitelist
            "https://gist.github.com.evil.io"
        ]

        for urlString in spoofingPayloads {
            let validated = SafeURLValidator.validate(urlString: urlString)
            XCTAssertNil(validated, "Host spoofing attempt MUST be rejected: \(urlString)")
            XCTAssertFalse(SafeURLValidator.isValid(urlString: urlString))
        }
    }

    func testSafeURLValidatorRejectsNonStandardPorts() {
        let badPorts = [
            "https://github.com:80/releases",
            "https://github.com:8080/releases",
            "https://github.com:8443/releases",
            "https://github.com:22/releases",
            "https://api.github.com:3000/releases"
        ]

        for urlString in badPorts {
            let validated = SafeURLValidator.validate(urlString: urlString)
            XCTAssertNil(validated, "Non-standard HTTPS port MUST be rejected: \(urlString)")
        }

        // Standard port 443 and omitted port must be accepted
        XCTAssertNotNil(SafeURLValidator.validate(urlString: "https://github.com:443/releases"))
        XCTAssertNotNil(SafeURLValidator.validate(urlString: "https://github.com/releases"))
    }

    func testSafeURLValidatorPermitsLegitimateGitHubReleaseURLs() {
        let legitimateURLs = [
            "https://github.com/WycDev/SystemResourceViewer",
            "https://github.com/WycDev/SystemResourceViewer/releases/latest",
            "https://github.com/WycDev/SystemResourceViewer/releases/tag/v2.0.0",
            "https://github.com/WycDev/SystemResourceViewer/archive/refs/tags/v2.0.0.zip",
            "https://api.github.com/repos/WycDev/SystemResourceViewer/releases",
            "https://api.github.com/repos/WycDev/SystemResourceViewer/releases/latest"
        ]

        for urlString in legitimateURLs {
            let validated = SafeURLValidator.validate(urlString: urlString)
            XCTAssertNotNil(validated, "Legitimate release URL must be accepted: \(urlString)")
            XCTAssertEqual(validated?.scheme, "https")
            XCTAssertTrue(SafeURLValidator.isValid(urlString: urlString))
        }
    }

    func testSafeURLValidatorMalformedAndEdgeCaseInputs() {
        let malformed = [
            "",
            "   ",
            "\n\t\r",
            "https://",
            "://github.com",
            "https:///path",
            "https:// github.com",
            "https://github .com",
            String(repeating: "a", count: 10_000)
        ]

        for str in malformed {
            let validated = SafeURLValidator.validate(urlString: str)
            XCTAssertNil(validated, "Malformed string should return nil: \(str.prefix(30))...")
            XCTAssertFalse(SafeURLValidator.isValid(urlString: str))
        }
    }

    // MARK: - 3. SensitiveDataSanitizer & PrivacySettings Adversarial Stress Tests

    func testSensitiveDataSanitizerMultipleInterleavedCredentials() {
        let complexCLI = [
            "python3 worker.py",
            "--api-key=sk-ant-api03-abcdef1234567890abcdef1234567890",
            "--github-pat=ghp_123456789012345678901234567890123456",
            "--aws-key=AKIAIOSFODNN7EXAMPLE",
            "--db=postgres://dbuser:MySuperSecretDbPassword!@db.internal.cloud:5432/analytics",
            "--password=CommandLinePassword123",
            "-p ShortPassword456",
            "-H 'Authorization: Bearer myBearerToken12345678901234567890'"
        ].joined(separator: " ")

        let sanitized = SensitiveDataSanitizer.sanitize(argument: complexCLI)

        // Verify none of the cleartext secrets remain
        XCTAssertFalse(sanitized.contains("sk-ant-api03-abcdef1234567890abcdef1234567890"))
        XCTAssertFalse(sanitized.contains("ghp_123456789012345678901234567890123456"))
        XCTAssertFalse(sanitized.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(sanitized.contains("MySuperSecretDbPassword!"))
        XCTAssertFalse(sanitized.contains("CommandLinePassword123"))
        XCTAssertFalse(sanitized.contains("ShortPassword456"))
        XCTAssertFalse(sanitized.contains("myBearerToken12345678901234567890"))

        // Verify that REDACTED replacement tokens exist
        XCTAssertTrue(sanitized.contains("***REDACTED***"))
    }

    func testSensitiveDataSanitizerNestedQuotesAndEscapedCharacters() {
        let nested1 = #"bash -c "curl -H 'Authorization: Bearer secrettoken12345678901234567890' https://api.com""#
        let san1 = SensitiveDataSanitizer.sanitize(argument: nested1)
        XCTAssertFalse(san1.contains("secrettoken12345678901234567890"))
        XCTAssertTrue(san1.contains("***REDACTED***"))

        let nested2 = #"node -e "const key = 'sk-proj-012345678901234567890123456789';""#
        let san2 = SensitiveDataSanitizer.sanitize(argument: nested2)
        XCTAssertFalse(san2.contains("sk-proj-012345678901234567890123456789"))
        XCTAssertTrue(san2.contains("***REDACTED***"))
    }

    func testSensitiveDataSanitizerBoundaryKeyLengths() {
        // Tokens shorter than minimum threshold must NOT be falsely masked
        let shortTokens = [
            "sk-short", // only 8 chars, pattern requires {20,}
            "ghp_short123", // only 12 chars
            "AKIA_TOO_SHORT", // not 16 chars
            "AKIA12345" // only 9 chars
        ]

        for token in shortTokens {
            let res = SensitiveDataSanitizer.sanitize(argument: token)
            XCTAssertEqual(res, token, "Short non-credential token '\(token)' should not be modified.")
        }
    }

    func testSensitiveDataSanitizerEmptyAndWhitespaceStrings() {
        XCTAssertEqual(SensitiveDataSanitizer.sanitize(argument: ""), "")
        XCTAssertEqual(SensitiveDataSanitizer.sanitize(argument: "   "), "   ")
        XCTAssertEqual(SensitiveDataSanitizer.sanitize(argument: "\n\t"), "\n\t")
        XCTAssertEqual(SensitiveDataSanitizer.sanitize(arguments: []), [])
    }

    func testSensitiveDataSanitizerExtremeScale100KBPlusPerformance() {
        // Construct a massive 150KB command line string
        let baseLine = "node server.js --config=/etc/app/config.json --worker-id=42 --cluster=production "
        let repetitions = 2000 // ~160,000 characters (160 KB)
        var massiveString = String(repeating: baseLine, count: repetitions)

        // Inject 5 sensitive credentials at 0%, 25%, 50%, 75%, and 100% marks
        let token1 = "sk-ant-api03-abcdef1234567890abcdef1234567890"
        let token2 = "ghp_123456789012345678901234567890123456"
        let token3 = "AKIAIOSFODNN7EXAMPLE"
        
        massiveString += " --token=\(token1) "
        massiveString += String(repeating: "arg=value ", count: 500)
        massiveString += " --github=\(token2) "
        massiveString += String(repeating: "arg=value ", count: 500)
        massiveString += " --aws-key=\(token3)"

        let totalLength = massiveString.count
        XCTAssertGreaterThan(totalLength, 100_000, "String must be greater than 100KB (actual: \(totalLength) chars).")

        let startTime = CFAbsoluteTimeGetCurrent()
        let sanitized = SensitiveDataSanitizer.sanitize(argument: massiveString)
        let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime

        // Assert performance: processing 160KB must take less than 150ms (ReDoS defense)
        XCTAssertLessThan(elapsedTime, 0.150, "Sanitizing 160KB command line took \(elapsedTime)s, expected < 0.150s")

        // Assert all injected credentials were redacted
        XCTAssertFalse(sanitized.contains(token1), "Token 1 must be redacted from 160KB payload")
        XCTAssertFalse(sanitized.contains(token2), "Token 2 must be redacted from 160KB payload")
        XCTAssertFalse(sanitized.contains(token3), "Token 3 must be redacted from 160KB payload")
        XCTAssertTrue(sanitized.contains("***REDACTED***"))
    }

    func testPrivacySettingsIPv4MaskingVariations() {
        var settings = PrivacySettings(maskLocalIPAddress: true)

        let ipCases = [
            ("192.168.1.1", "192.168.*.*"),
            ("10.0.0.254", "10.0.*.*"),
            ("172.16.254.1", "172.16.*.*"),
            ("127.0.0.1", "127.0.*.*"),
            ("invalid_ip", "•••.•••.•••.•••"),
            ("1.2.3", "•••.•••.•••.•••")
        ]

        for (input, expected) in ipCases {
            XCTAssertEqual(settings.sanitize(ipv4: input), expected)
        }

        // When disabled, original IP is preserved
        settings.maskLocalIPAddress = false
        XCTAssertEqual(settings.sanitize(ipv4: "192.168.1.1"), "192.168.1.1")
        XCTAssertEqual(settings.sanitize(ipv4: "10.0.0.254"), "10.0.0.254")
    }

    func testPrivacySettingsArgumentsArraySanitization() {
        let settings = PrivacySettings(maskSensitiveArguments: true)
        let args = [
            "/usr/bin/curl",
            "-H",
            "Authorization: Bearer supersecrettoken12345678901234567890",
            "https://api.github.com/user",
            "--verbose"
        ]

        let sanitized = settings.sanitize(arguments: args)
        XCTAssertEqual(sanitized[0], "/usr/bin/curl")
        XCTAssertEqual(sanitized[1], "-H")
        XCTAssertTrue(sanitized[2].contains("***REDACTED***"))
        XCTAssertFalse(sanitized[2].contains("supersecrettoken12345678901234567890"))
        XCTAssertEqual(sanitized[3], "https://api.github.com/user")
        XCTAssertEqual(sanitized[4], "--verbose")
    }
}

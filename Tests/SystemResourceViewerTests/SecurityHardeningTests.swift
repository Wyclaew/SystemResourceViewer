import XCTest
@testable import SystemResourceViewer

final class SecurityHardeningTests: XCTestCase {

    // MARK: - 1. ProcessGuard Blacklist & Protection Tests

    func testProcessGuardBlockedPIDs() {
        // PID 0 (kernel idle / swapper)
        XCTAssertTrue(ProcessGuard.isProtected(pid: 0))
        let pid0Status = ProcessGuard.protectionStatus(pid: 0)
        XCTAssertTrue(pid0Status.protected)
        XCTAssertEqual(pid0Status.reason, "Cannot terminate system initialization process (PID 0).")

        // PID 1 (launchd init daemon)
        XCTAssertTrue(ProcessGuard.isProtected(pid: 1))
        let pid1Status = ProcessGuard.protectionStatus(pid: 1)
        XCTAssertTrue(pid1Status.protected)
        XCTAssertEqual(pid1Status.reason, "Cannot terminate system initialization process (PID 1).")

        // Negative PIDs
        XCTAssertTrue(ProcessGuard.isProtected(pid: -1))
        let neg1Status = ProcessGuard.protectionStatus(pid: -1)
        XCTAssertTrue(neg1Status.protected)
        XCTAssertEqual(neg1Status.reason, "Cannot terminate system initialization process (PID -1).")

        XCTAssertTrue(ProcessGuard.isProtected(pid: -9999))
        let neg99Status = ProcessGuard.protectionStatus(pid: -9999)
        XCTAssertTrue(neg99Status.protected)
        XCTAssertEqual(neg99Status.reason, "Cannot terminate system initialization process (PID -9999).")
    }

    func testProcessGuardSelfPIDProtection() {
        let currentPID = getpid()
        XCTAssertTrue(ProcessGuard.isProtected(pid: currentPID))
        let selfStatus = ProcessGuard.protectionStatus(pid: currentPID)
        XCTAssertTrue(selfStatus.protected)
        XCTAssertEqual(selfStatus.reason, "Cannot terminate the active Resource Monitor application directly.")
    }

    func testProcessGuardParentPIDProtection() {
        let ppid = getppid()
        if ppid > 1 {
            XCTAssertTrue(ProcessGuard.isProtected(pid: ppid))
            let parentStatus = ProcessGuard.protectionStatus(pid: ppid)
            XCTAssertTrue(parentStatus.protected)
            XCTAssertEqual(parentStatus.reason, "Cannot terminate parent host process (PID \(ppid)).")
        }
    }

    func testProcessGuardCriticalSystemNames() {
        let criticalNames = [
            "WindowServer",
            "loginwindow",
            "diskarbitrationd",
            "syspolicyd",
            "opendirectoryd",
            "launchd",
            "kernel_task",
            "securityd",
            "trustd",
            "notifyd",
            "configd",
            "powerd",
            "fseventsd",
            "coreauthd",
            "Dock",
            "Finder",
            "SystemResourceViewer",
            "Resource Monitor"
        ]

        for name in criticalNames {
            XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: name), "Process '\(name)' must return isProtected == true.")
            let status = ProcessGuard.protectionStatus(pid: 99999, name: name)
            XCTAssertTrue(status.protected, "Process '\(name)' must be protected by ProcessGuard.")
            XCTAssertNotNil(status.reason)
            XCTAssertTrue(status.reason?.contains(name) == true || status.reason?.contains("critical") == true)
        }
    }

    func testProcessGuardCaseInsensitiveMatching() {
        XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: "windowserver"))
        XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: "LOGINWINDOW"))
        XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: "DiskArbitrationD"))
        XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: "sysPOLICYD"))
    }

    func testProcessGuardBlockedBundleIdentifiers() {
        let bundleIDs = [
            "com.apple.WindowServer",
            "com.apple.loginwindow",
            "com.apple.dock",
            "com.apple.finder",
            "com.apple.syspolicyd",
            "com.apple.diskarbitrationd",
            "com.apple.opendirectoryd",
            "com.apple.securityd",
            "com.apple.launchd"
        ]

        for bid in bundleIDs {
            XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, bundleIdentifier: bid))
            let status = ProcessGuard.protectionStatus(pid: 99999, bundleIdentifier: bid)
            XCTAssertTrue(status.protected, "Bundle ID '\(bid)' must be protected by ProcessGuard.")
        }
    }

    func testProcessGuardProtectedPathPrefixes() {
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
            XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, path: path))
            let status = ProcessGuard.protectionStatus(pid: 99999, path: path)
            XCTAssertTrue(status.protected, "Path '\(path)' must be protected by ProcessGuard.")
        }
    }

    func testProcessGuardPIDOnlyResolutionWithNilName() {
        // System daemons where name: nil is supplied but path or PID indicates a protected component
        let protectedPaths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer",
            "/usr/sbin/securityd",
            "/usr/sbin/notifyd",
            "/System/Library/CoreServices/powerd.bundle/powerd",
            "/usr/libexec/diskarbitrationd"
        ]

        for path in protectedPaths {
            // Test with name explicitly nil
            XCTAssertTrue(
                ProcessGuard.isProtected(pid: 99999, name: nil, path: path),
                "Process at path '\(path)' must be protected when name is nil."
            )
            let status = ProcessGuard.protectionStatus(pid: 99999, name: nil, path: path)
            XCTAssertTrue(status.protected, "Protection status for '\(path)' must be protected.")
            XCTAssertNotNil(status.reason)
        }
    }

    func testProcessGuardExpandedPathPrefixes() {
        XCTAssertTrue(ProcessGuard.protectedPathPrefixes.contains("/System/Library/PrivateFrameworks/"))
        XCTAssertTrue(ProcessGuard.protectedPathPrefixes.contains("/usr/sbin/"))
        XCTAssertTrue(ProcessGuard.protectedPathPrefixes.contains("/System/Library/CoreServices/"))
        XCTAssertTrue(ProcessGuard.protectedPathPrefixes.contains("/usr/libexec/"))
        XCTAssertTrue(ProcessGuard.protectedPathPrefixes.contains("/System/Library/Frameworks/"))
    }

    func testProcessGuardUnprotectedNormalProcesses() {
        let userProcesses = ["Safari", "Calculator", "node", "python3", "Terminal", "Xcode", "Visual Studio Code"]
        for name in userProcesses {
            XCTAssertFalse(ProcessGuard.isProtected(pid: 54321, name: name, path: "/Applications/\(name).app"))
            let status = ProcessGuard.protectionStatus(pid: 54321, name: name, path: "/Applications/\(name).app")
            XCTAssertFalse(status.protected, "User process '\(name)' should not be blocked.")
            XCTAssertNil(status.reason)
        }
    }

    func testProcessActionIntegratesProcessGuard() {
        // WindowServer termination rejection
        let termWindowServer = ProcessAction.terminate(pid: 99999, name: "WindowServer")
        XCTAssertEqual(termWindowServer, .failure("Cannot terminate critical system process 'WindowServer' (PID 99999)."))

        // loginwindow force kill rejection
        let forceLoginwindow = ProcessAction.forceKill(pid: 99999, name: "loginwindow")
        XCTAssertEqual(forceLoginwindow, .failure("Cannot terminate critical system process 'loginwindow' (PID 99999)."))

        // diskarbitrationd rejection
        let termDiskArb = ProcessAction.terminate(pid: 99999, name: "diskarbitrationd")
        XCTAssertEqual(termDiskArb, .failure("Cannot terminate critical system process 'diskarbitrationd' (PID 99999)."))

        // syspolicyd rejection
        let termSyspolicy = ProcessAction.terminate(pid: 99999, name: "syspolicyd")
        XCTAssertEqual(termSyspolicy, .failure("Cannot terminate critical system process 'syspolicyd' (PID 99999)."))

        // opendirectoryd rejection
        let termOpenDir = ProcessAction.terminate(pid: 99999, name: "opendirectoryd")
        XCTAssertEqual(termOpenDir, .failure("Cannot terminate critical system process 'opendirectoryd' (PID 99999)."))

        // launchd rejection
        let termLaunchd = ProcessAction.terminate(pid: 99999, name: "launchd")
        XCTAssertEqual(termLaunchd, .failure("Cannot terminate critical system process 'launchd' (PID 99999)."))
    }

    func testProcessItemIsProtectedProperty() {
        let protectedItem = ProcessItem(
            id: 200,
            name: "WindowServer",
            bundleIdentifier: "com.apple.WindowServer",
            cpuPercentage: 5.0,
            memoryBytes: 100_000_000
        )
        XCTAssertTrue(protectedItem.isProtected)

        let initItem = ProcessItem(
            id: 1,
            name: "launchd",
            cpuPercentage: 0.1,
            memoryBytes: 10_000_000
        )
        XCTAssertTrue(initItem.isProtected)

        let userAppItem = ProcessItem(
            id: 12345,
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            cpuPercentage: 2.0,
            memoryBytes: 200_000_000
        )
        XCTAssertFalse(userAppItem.isProtected)
    }

    // MARK: - 2. SafeURLValidator Tests

    func testSafeURLValidatorValidGitHubURLs() {
        let validURLs = [
            "https://github.com/WycDev/SystemResourceViewer",
            "https://github.com/WycDev/SystemResourceViewer/releases/latest",
            "https://github.com/WycDev/SystemResourceViewer/releases/tag/v2.0.0",
            "https://api.github.com/repos/WycDev/SystemResourceViewer/releases"
        ]

        for urlString in validURLs {
            let validated = SafeURLValidator.validate(urlString: urlString)
            XCTAssertNotNil(validated, "Valid GitHub URL should pass: \(urlString)")
            XCTAssertEqual(validated?.scheme, "https")
            XCTAssertTrue(SafeURLValidator.isValid(urlString: urlString))
        }
    }

    func testSafeURLValidatorRejectsInsecureHttpScheme() {
        let insecure = "http://github.com/WycDev/SystemResourceViewer"
        XCTAssertNil(SafeURLValidator.validate(urlString: insecure))
        XCTAssertFalse(SafeURLValidator.isValid(urlString: insecure))
    }

    func testSafeURLValidatorRejectsDangerousSchemes() {
        let dangerousURLs = [
            "file:///etc/passwd",
            "file:///Applications/Calculator.app",
            "applescript://com.apple.ScriptEditor?cmd=beep",
            "terminal://run-command",
            "javascript:alert(document.cookie)",
            "data:text/html,<script>alert(1)</script>",
            "ssh://git@github.com",
            "telnet://192.168.1.1:23"
        ]

        for urlString in dangerousURLs {
            XCTAssertNil(SafeURLValidator.validate(urlString: urlString), "Dangerous scheme must be rejected: \(urlString)")
            XCTAssertFalse(SafeURLValidator.isValid(urlString: urlString))
        }
    }

    func testSafeURLValidatorRejectsHostSpoofing() {
        let spoofedURLs = [
            "https://github.com.evil.com/releases",
            "https://evil-github.com/releases",
            "https://notgithub.com/repo",
            "https://github.com.attacker.org/WycDev",
            "https://attacker.com/?redirect=github.com"
        ]

        for urlString in spoofedURLs {
            XCTAssertNil(SafeURLValidator.validate(urlString: urlString), "Spoofed host must be rejected: \(urlString)")
            XCTAssertFalse(SafeURLValidator.isValid(urlString: urlString))
        }
    }

    func testSafeURLValidatorRejectsEmbeddedUserinfo() {
        let userinfoURL = "https://user:password@github.com/repo"
        XCTAssertNil(SafeURLValidator.validate(urlString: userinfoURL))
    }

    func testSafeURLValidatorRejectsNonStandardPorts() {
        let nonStandardPortURL = "https://github.com:8443/releases"
        XCTAssertNil(SafeURLValidator.validate(urlString: nonStandardPortURL))
    }

    func testSafeURLValidatorRejectsMalformedAndEmptyStrings() {
        let malformed = ["", "   ", "not_a_url", "https://", "://invalid", "   \n\t  "]
        for str in malformed {
            XCTAssertNil(SafeURLValidator.validate(urlString: str))
            XCTAssertFalse(SafeURLValidator.isValid(urlString: str))
        }
    }

    func testSafeURLValidatorCustomAllowedHosts() {
        let customHosts: Set<String> = ["apple.com", "developer.apple.com"]
        XCTAssertNotNil(SafeURLValidator.validate(urlString: "https://apple.com/macos", allowedHosts: customHosts))
        XCTAssertNotNil(SafeURLValidator.validate(urlString: "https://developer.apple.com/documentation", allowedHosts: customHosts))
        XCTAssertNil(SafeURLValidator.validate(urlString: "https://github.com/repo", allowedHosts: customHosts))
    }

    // MARK: - 3. PrivacySettings & Sensitive Credential Masking Tests

    func testDefaultPrivacySettingsValues() {
        let defaults = PrivacySettings.defaultSettings
        XCTAssertTrue(defaults.maskSensitiveArguments)
        XCTAssertTrue(defaults.allowExternalSocketProbe)
        XCTAssertFalse(defaults.maskLocalIPAddress)
        XCTAssertFalse(defaults.hideSystemProcessesByDefault)
    }

    func testPrivacySettingsCodableRoundtrip() throws {
        let original = PrivacySettings(
            maskSensitiveArguments: false,
            allowExternalSocketProbe: false,
            maskLocalIPAddress: true,
            hideSystemProcessesByDefault: true
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PrivacySettings.self, from: encoded)

        XCTAssertEqual(original, decoded)
    }

    func testSensitiveDataSanitizerOpenAITokens() {
        let input = "python train.py --api-key=sk-ant-api03-abcdef1234567890abcdef1234567890 --model=claude"
        let sanitized = SensitiveDataSanitizer.sanitize(argument: input)
        XCTAssertFalse(sanitized.contains("sk-ant-api03-abcdef1234567890abcdef1234567890"))
        XCTAssertTrue(sanitized.contains("***REDACTED***"))
    }

    func testSensitiveDataSanitizerGitHubTokens() {
        let input = "git clone https://ghp_123456789012345678901234567890123456@github.com/org/repo.git"
        let sanitized = SensitiveDataSanitizer.sanitize(argument: input)
        XCTAssertFalse(sanitized.contains("ghp_123456789012345678901234567890123456"))
        XCTAssertTrue(sanitized.contains("***REDACTED***"))
    }

    func testSensitiveDataSanitizerAWSAccessKeys() {
        let input = "aws s3 sync . s3://bucket --access-key=AKIAIOSFODNN7EXAMPLE"
        let sanitized = SensitiveDataSanitizer.sanitize(argument: input)
        XCTAssertFalse(sanitized.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(sanitized.contains("***REDACTED***"))
    }

    func testSensitiveDataSanitizerCLIPasswordFlags() {
        let input1 = "mysql -u admin --password=SuperSecretPassword123 mydb"
        let sanitized1 = SensitiveDataSanitizer.sanitize(argument: input1)
        XCTAssertFalse(sanitized1.contains("SuperSecretPassword123"))
        XCTAssertEqual(sanitized1, "mysql -u admin --password=***REDACTED*** mydb")

        let input2 = "sshpass -p TopSecretKey ssh user@remote"
        let sanitized2 = SensitiveDataSanitizer.sanitize(argument: input2)
        XCTAssertFalse(sanitized2.contains("TopSecretKey"))
        XCTAssertEqual(sanitized2, "sshpass -p ***REDACTED*** ssh user@remote")
    }

    func testSensitiveDataSanitizerBearerTokens() {
        let input = "curl -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.t-ID' https://api.site.com"
        let sanitized = SensitiveDataSanitizer.sanitize(argument: input)
        XCTAssertFalse(sanitized.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.t-ID"))
        XCTAssertTrue(sanitized.contains("Bearer ***REDACTED***"))
    }

    func testSensitiveDataSanitizerDatabaseURIs() {
        let input = "psql postgres://admin:SuperSecretPass@db.internal.net:5432/production"
        let sanitized = SensitiveDataSanitizer.sanitize(argument: input)
        XCTAssertFalse(sanitized.contains("SuperSecretPass"))
        XCTAssertEqual(sanitized, "psql postgres://admin:***REDACTED***@db.internal.net:5432/production")
    }

    func testSensitiveDataSanitizerPreservesUnsensitiveArguments() {
        let cleanArgs = ["node", "server.js", "--port=8080", "--env=production", "--verbose"]
        let sanitized = SensitiveDataSanitizer.sanitize(arguments: cleanArgs)
        XCTAssertEqual(cleanArgs, sanitized)
    }

    func testSensitiveDataSanitizerMultiTokenFlagArray() {
        // 1. Password flags (--password and -p)
        let passArgs = ["app", "--password", "MySecretPassword123", "-p", "AnotherSecretKey"]
        let sanitizedPass = SensitiveDataSanitizer.sanitize(arguments: passArgs)
        XCTAssertEqual(sanitizedPass, ["app", "--password", "***REDACTED***", "-p", "***REDACTED***"])

        // 2. Token flags (--token)
        let tokenArgs = ["cli", "--token", "ghp_mock_token_value_xyz"]
        let sanitizedToken = SensitiveDataSanitizer.sanitize(arguments: tokenArgs)
        XCTAssertEqual(sanitizedToken, ["cli", "--token", "***REDACTED***"])

        // 3. API key flags (--api-key, --api_key, --apikey)
        let apiKeyArgs = ["fetch", "--api-key", "SuperSecretAPIKey", "--api_key", "Key2", "--apikey", "Key3"]
        let sanitizedAPIKey = SensitiveDataSanitizer.sanitize(arguments: apiKeyArgs)
        XCTAssertEqual(sanitizedAPIKey, ["fetch", "--api-key", "***REDACTED***", "--api_key", "***REDACTED***", "--apikey", "***REDACTED***"])

        // 4. Secret flags (--secret)
        let secretArgs = ["deploy", "--secret", "VaultSecretString!"]
        let sanitizedSecret = SensitiveDataSanitizer.sanitize(arguments: secretArgs)
        XCTAssertEqual(sanitizedSecret, ["deploy", "--secret", "***REDACTED***"])

        // 5. Auth flags (--auth, --auth-token)
        let authArgs = ["connect", "--auth", "BasicXYZ123", "--auth-token", "TokenABC"]
        let sanitizedAuth = SensitiveDataSanitizer.sanitize(arguments: authArgs)
        XCTAssertEqual(sanitizedAuth, ["connect", "--auth", "***REDACTED***", "--auth-token", "***REDACTED***"])

        // 6. Case insensitivity
        let upperArgs = ["service", "--PASSWORD", "CaseSecret", "-P", "ShortSecret"]
        let sanitizedUpper = SensitiveDataSanitizer.sanitize(arguments: upperArgs)
        XCTAssertEqual(sanitizedUpper, ["service", "--PASSWORD", "***REDACTED***", "-P", "***REDACTED***"])

        // 7. Trailing flag at array boundary
        let trailingArgs = ["command", "--password"]
        let sanitizedTrailing = SensitiveDataSanitizer.sanitize(arguments: trailingArgs)
        XCTAssertEqual(sanitizedTrailing, ["command", "--password"])

        // 8. Integration through PrivacySettings.sanitize(arguments:)
        let settings = PrivacySettings(maskSensitiveArguments: true)
        let mixed = ["run", "--password", "SecretValue", "--host", "127.0.0.1", "--token", "TokenVal"]
        XCTAssertEqual(settings.sanitize(arguments: mixed), ["run", "--password", "***REDACTED***", "--host", "127.0.0.1", "--token", "***REDACTED***"])
    }

    func testPrivacySettingsToggleMaskingOff() {
        var settings = PrivacySettings(maskSensitiveArguments: false)
        let sensitive = "run --password=Secret123"
        XCTAssertEqual(settings.sanitize(argument: sensitive), sensitive)

        settings.maskSensitiveArguments = true
        XCTAssertEqual(settings.sanitize(argument: sensitive), "run --password=***REDACTED***")
    }

    func testPrivacySettingsLocalIPAddressMasking() {
        var settings = PrivacySettings(maskLocalIPAddress: false)
        XCTAssertEqual(settings.sanitize(ipv4: "192.168.1.105"), "192.168.1.105")

        settings.maskLocalIPAddress = true
        XCTAssertEqual(settings.sanitize(ipv4: "192.168.1.105"), "192.168.*.*")
        XCTAssertEqual(settings.sanitize(ipv4: "10.0.0.1"), "10.0.*.*")
        XCTAssertEqual(settings.sanitize(ipv4: "—"), "•••.•••.•••.•••")
    }

    @MainActor
    func testLocalIPAddressMaskingInDashboardViewModel() {
        let vm = DashboardViewModel(interval: 10.0)
        let sampleIP = "192.168.1.100"

        // Default: maskLocalIPAddress is false
        vm.privacySettings.maskLocalIPAddress = false
        XCTAssertEqual(vm.privacySettings.sanitize(ipv4: sampleIP), "192.168.1.100")

        // Masking enabled
        vm.privacySettings.maskLocalIPAddress = true
        XCTAssertEqual(vm.privacySettings.sanitize(ipv4: sampleIP), "192.168.*.*")
        XCTAssertEqual(vm.privacySettings.sanitize(ipv4: "10.20.30.40"), "10.20.*.*")
        XCTAssertEqual(vm.privacySettings.sanitize(ipv4: "—"), "•••.•••.•••.•••")
    }

    // MARK: - 4. NetworkMonitorService Privacy Socket Probe Toggle Tests

    func testNetworkMonitorServicePrivacyToggle() async {
        let service = NetworkMonitorService(allowExternalSocketProbe: false)
        let initialAllowed = await service.allowExternalSocketProbe
        XCTAssertFalse(initialAllowed)

        await service.setAllowExternalSocketProbe(true)
        let updatedAllowed = await service.allowExternalSocketProbe
        XCTAssertTrue(updatedAllowed)

        await service.setAllowExternalSocketProbe(false)
        let disabledAllowed = await service.allowExternalSocketProbe
        XCTAssertFalse(disabledAllowed)
    }

    func testMetricsSchedulerPrivacyToggleIntegration() async {
        let scheduler = MetricsScheduler(interval: 5.0)
        await scheduler.setAllowExternalSocketProbe(false)
        await scheduler.setAllowExternalSocketProbe(true)
    }

    // MARK: - 5. Two-Step Termination Confirmation in DashboardViewModel

    @MainActor
    func testDashboardViewModelTwoStepTerminationFlow() {
        let vm = DashboardViewModel(interval: 10.0)

        XCTAssertNil(vm.pendingTermination)
        XCTAssertFalse(vm.showTerminationConfirmation)

        // 1. Request termination
        vm.requestProcessTermination(pid: 12345, name: "WorkerTask", force: false)
        XCTAssertTrue(vm.showTerminationConfirmation)
        XCTAssertEqual(vm.pendingTermination?.id, 12345)
        XCTAssertEqual(vm.pendingTermination?.name, "WorkerTask")
        XCTAssertFalse(vm.pendingTermination?.isForce ?? true)

        // 2. Cancel termination
        vm.cancelProcessTermination()
        XCTAssertFalse(vm.showTerminationConfirmation)
        XCTAssertNil(vm.pendingTermination)

        // 3. Request force kill
        vm.requestProcessTermination(pid: 54321, name: "UnresponsiveTask", force: true)
        XCTAssertTrue(vm.showTerminationConfirmation)
        XCTAssertTrue(vm.pendingTermination?.isForce ?? false)

        // 4. Confirm execution (non-existent PID returns ESRCH failure cleanly)
        let result = vm.confirmProcessTermination()
        XCTAssertNotNil(result)
        XCTAssertFalse(vm.showTerminationConfirmation)
        XCTAssertNil(vm.pendingTermination)
        XCTAssertNotNil(vm.lastActionResultMessage)
    }

    @MainActor
    func testDashboardViewModelRejectsProtectedProcessTermination() {
        let vm = DashboardViewModel(interval: 10.0)

        // Attempting to terminate WindowServer via confirmProcessTermination
        let res = vm.confirmProcessTermination(pid: 99999, name: "WindowServer", force: false)
        if case .failure(let reason) = res {
            XCTAssertTrue(reason.contains("WindowServer"))
            XCTAssertTrue(reason.contains("critical system process"))
        } else {
            XCTFail("WindowServer termination must be rejected by ProcessGuard.")
        }

        // Attempting to terminate loginwindow
        let res2 = vm.confirmProcessTermination(pid: 99999, name: "loginwindow", force: true)
        if case .failure(let reason) = res2 {
            XCTAssertTrue(reason.contains("loginwindow"))
        } else {
            XCTFail("loginwindow termination must be rejected by ProcessGuard.")
        }
    }

    @MainActor
    func testDashboardViewModelSafeURLUpdateIntegration() {
        let vm = DashboardViewModel(interval: 10.0)

        // Dangerous URL in update release
        let maliciousRelease = GitHubRelease(
            tagName: "v2.0.0",
            name: "Malicious Update",
            body: "Pwned",
            htmlUrl: "applescript://com.apple.ScriptEditor?cmd=beep",
            publishedAt: "2026-11-17T00:00:00Z"
        )

        vm.pendingUpdate = maliciousRelease
        vm.showUpdateConfirmation = true

        vm.confirmUpdateAndOpenBrowser()
        // Should close confirmation and safely abort without executing applescript
        XCTAssertFalse(vm.showUpdateConfirmation)
    }
}

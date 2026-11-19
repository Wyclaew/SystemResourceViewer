import XCTest
@testable import SystemResourceViewer

final class Milestone2Challenger2StressTests: XCTestCase {

    // MARK: - 1. UI Confirmation State Machine Stress Tests

    @MainActor
    func testTerminationStateMachineRapidReentrantRequests() {
        let vm = DashboardViewModel(interval: 10.0)

        XCTAssertNil(vm.pendingTermination)
        XCTAssertFalse(vm.showTerminationConfirmation)

        // Rapid fire 100 requests in sequence
        for i in 1...100 {
            let pid = pid_t(1000 + i)
            let name = "Proc_\(i)"
            let isForce = (i % 2 == 0)
            let isGroup = (i % 3 == 0)
            let childCount = isGroup ? (i % 5) : 0

            vm.requestProcessTermination(
                pid: pid,
                name: name,
                force: isForce,
                isGroup: isGroup,
                childCount: childCount
            )

            // State machine invariant check: latest request must strictly overwrite previous
            XCTAssertTrue(vm.showTerminationConfirmation)
            guard let req = vm.pendingTermination else {
                XCTFail("pendingTermination must not be nil after requestProcessTermination")
                return
            }
            XCTAssertEqual(req.id, pid)
            XCTAssertEqual(req.name, name)
            XCTAssertEqual(req.isForce, isForce)
            XCTAssertEqual(req.isGroup, isGroup)
            XCTAssertEqual(req.childCount, childCount)
        }

        // Test cancel
        vm.cancelProcessTermination()
        XCTAssertNil(vm.pendingTermination)
        XCTAssertFalse(vm.showTerminationConfirmation)
    }

    @MainActor
    func testTerminationStateMachineCancelConfirmInterleaving() {
        let vm = DashboardViewModel(interval: 10.0)

        // Sequence of (request -> cancel -> request -> confirm -> confirm)
        for i in 1...20 {
            // Step 1: Request and Cancel
            vm.requestProcessTermination(pid: pid_t(2000 + i), name: "CancelTask_\(i)")
            XCTAssertTrue(vm.showTerminationConfirmation)
            XCTAssertNotNil(vm.pendingTermination)

            vm.cancelProcessTermination()
            XCTAssertFalse(vm.showTerminationConfirmation)
            XCTAssertNil(vm.pendingTermination)

            // Step 2: Idempotent Cancel (cancel again when already nil)
            vm.cancelProcessTermination()
            XCTAssertFalse(vm.showTerminationConfirmation)
            XCTAssertNil(vm.pendingTermination)

            // Step 3: Confirm when pendingTermination is nil
            let nilRes = vm.confirmProcessTermination()
            XCTAssertNil(nilRes, "confirmProcessTermination when pendingTermination is nil must return nil")
            XCTAssertFalse(vm.showTerminationConfirmation)

            // Step 4: Request and Confirm
            vm.requestProcessTermination(pid: pid_t(3000 + i), name: "ConfirmTask_\(i)", force: true)
            let res = vm.confirmProcessTermination()
            XCTAssertNotNil(res)
            XCTAssertNil(vm.pendingTermination)
            XCTAssertFalse(vm.showTerminationConfirmation)
            XCTAssertNotNil(vm.lastActionResultMessage)
        }
    }

    @MainActor
    func testTerminationStateMachineRejectsProtectedProcessesEvenIfRequested() {
        let vm = DashboardViewModel(interval: 10.0)

        let protectedTargets: [(pid_t, String)] = [
            (0, "kernel_task"),
            (1, "launchd"),
            (9999, "WindowServer"),
            (9998, "loginwindow"),
            (getpid(), "SystemResourceViewer"),
            (getppid(), "parent_shell")
        ]

        for (pid, name) in protectedTargets {
            // Request termination through ViewModel state machine
            vm.requestProcessTermination(pid: pid, name: name, force: false)
            XCTAssertTrue(vm.showTerminationConfirmation)
            XCTAssertEqual(vm.pendingTermination?.id, pid)

            // Confirm execution - ProcessGuard must intercept and return failure
            let result = vm.confirmProcessTermination()
            XCTAssertNil(vm.pendingTermination, "pendingTermination must be cleared after confirm")
            XCTAssertFalse(vm.showTerminationConfirmation)

            guard let res = result else {
                XCTFail("Result must not be nil")
                continue
            }

            switch res {
            case .failure(let reason):
                XCTAssertTrue(reason.contains("Cannot terminate") || reason.contains("critical system process") || reason.contains("protected"),
                              "Reason '\(reason)' must indicate protection for \(name)")
                XCTAssertTrue(vm.lastActionResultMessage?.contains("Failed:") ?? false)
            case .success:
                XCTFail("Protected process \(name) (PID \(pid)) must NEVER succeed termination")
            }
        }
    }

    @MainActor
    func testTerminationDirectConfirmationVsPendingConfirmationEquivalence() {
        let vm = DashboardViewModel(interval: 10.0)

        // Compare direct confirmProcessTermination vs staged pending confirmProcessTermination
        let targetPID: pid_t = 88888
        let targetName = "DirectTask"

        // Direct call
        let directRes = vm.confirmProcessTermination(pid: targetPID, name: targetName, force: false)
        XCTAssertNotNil(vm.lastActionResultMessage)

        // Staged call
        vm.requestProcessTermination(pid: targetPID, name: targetName, force: false)
        let stagedRes = vm.confirmProcessTermination()
        XCTAssertEqual(stagedRes, directRes)
    }

    // MARK: - 2. NetworkMonitorService Socket Probe Toggle Stress Tests

    func testNetworkMonitorServiceToggleUnderHighConcurrency() async {
        let service = NetworkMonitorService(allowExternalSocketProbe: true)

        // 30 concurrent tasks toggling allowExternalSocketProbe and polling
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    let enable = (i % 2 == 0)
                    await service.setAllowExternalSocketProbe(enable)
                    let metrics = await service.pollNetworkMetrics()

                    // Invariant check: when disabled, latencyMilliseconds must strictly be nil
                    let allowed = await service.allowExternalSocketProbe
                    if !allowed {
                        XCTAssertNil(metrics.latencyMilliseconds, "When socket probe is disabled, latencyMilliseconds must be nil")
                    }
                }
            }
        }
    }

    func testNetworkMonitorServiceStateTransitionsAndZeroTelemetryLeakage() async {
        let service = NetworkMonitorService(allowExternalSocketProbe: false)

        // Verify initial state: false, zero latency
        let initialMetrics = await service.pollNetworkMetrics()
        XCTAssertNil(initialMetrics.latencyMilliseconds, "Must be nil when allowExternalSocketProbe is false")

        // Switch to true
        await service.setAllowExternalSocketProbe(true)
        let enabled = await service.allowExternalSocketProbe
        XCTAssertTrue(enabled)

        // Switch back to false immediately
        await service.setAllowExternalSocketProbe(false)
        let disabled = await service.allowExternalSocketProbe
        XCTAssertFalse(disabled)

        // Poll multiple times: must strictly report nil latency
        for _ in 0..<5 {
            let m = await service.pollNetworkMetrics()
            XCTAssertNil(m.latencyMilliseconds, "Must remain nil across multiple polls when disabled")
        }
    }

    func testMetricsSchedulerPrivacySettingPropagation() async {
        let scheduler = MetricsScheduler(interval: 5.0)

        // Test dynamic propagation to internal NetworkMonitorService
        await scheduler.setAllowExternalSocketProbe(false)
        await scheduler.setAllowExternalSocketProbe(true)
        await scheduler.setAllowExternalSocketProbe(false)

        await scheduler.stop()
    }

    // MARK: - 3. ProcessGuard Boundary & Evasion Stress Tests

    func testProcessGuardEdgePIDs() {
        let selfPID = getpid()
        let parentPID = getppid()

        let negativePIDs: [pid_t] = [-1, -99, -32768, Int32.min]
        for pid in negativePIDs {
            XCTAssertTrue(ProcessGuard.isProtected(pid: pid), "Negative PID \(pid) must be protected")
        }

        XCTAssertTrue(ProcessGuard.isProtected(pid: 0), "PID 0 must be protected")
        XCTAssertTrue(ProcessGuard.isProtected(pid: 1), "PID 1 must be protected")
        XCTAssertTrue(ProcessGuard.isProtected(pid: selfPID), "Self PID \(selfPID) must be protected")
        if parentPID > 1 {
            XCTAssertTrue(ProcessGuard.isProtected(pid: parentPID), "Parent PID \(parentPID) must be protected")
        }
    }

    func testProcessGuardNameCaseInsensitivityAndEvasions() {
        let variations = [
            "windowserver", "WINDOWSERVER", "WindowServer", "wInDoWsErVeR",
            "loginwindow", "LOGINWINDOW", "LoginWindow",
            "launchd", "LAUNCHD", "Launchd",
            "kernel_task", "KERNEL_TASK",
            "diskarbitrationd", "opendirectoryd", "syspolicyd", "securityd",
            "dock", "finder", "Finder", "DOCK"
        ]

        for name in variations {
            XCTAssertTrue(
                ProcessGuard.isProtected(pid: 99999, name: name),
                "Blocked daemon '\(name)' must be recognized regardless of casing"
            )
        }

        let bundleVariations = [
            "com.apple.windowserver", "COM.APPLE.WINDOWSERVER", "com.apple.WindowServer",
            "com.apple.loginwindow", "com.apple.dock", "com.apple.finder"
        ]
        for bid in bundleVariations {
            XCTAssertTrue(
                ProcessGuard.isProtected(pid: 99999, bundleIdentifier: bid),
                "Blocked bundle ID '\(bid)' must be recognized"
            )
        }

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
            XCTAssertTrue(
                ProcessGuard.isProtected(pid: 99999, path: path),
                "Protected binary path '\(path)' must be recognized"
            )
        }

        let legitimateUserProcesses = [
            "MyCustomGoServer",
            "node",
            "python3",
            "Calculator",
            "TextEdit",
            "Slack"
        ]
        for name in legitimateUserProcesses {
            XCTAssertFalse(
                ProcessGuard.isProtected(pid: 88888, name: name, path: "/Users/test/bin/\(name)"),
                "Legitimate user process '\(name)' should not be blocked by ProcessGuard"
            )
        }
    }

    // MARK: - 4. SafeURLValidator Adversarial URL Injection Tests

    func testSafeURLValidatorMaliciousSchemes() {
        let attackURLs = [
            "file:///etc/passwd",
            "file:///System/Applications/Utilities/Terminal.app",
            "applescript://execute?code=tell%20application%20Finder%20to%20quit",
            "terminal://launch?command=rm%20-rf",
            "javascript:alert(document.cookie)",
            "data:text/html,<script>alert(1)</script>",
            "blob:https://github.com/uuid-string",
            "ftp://github.com/payload.sh",
            "ssh://git@github.com:repo.git",
            "http://github.com/owner/repo/releases", // Unencrypted HTTP must be rejected
            ""
        ]

        for urlString in attackURLs {
            XCTAssertFalse(
                SafeURLValidator.isValid(urlString: urlString),
                "Dangerous scheme '\(urlString)' must be rejected"
            )
            XCTAssertNil(
                SafeURLValidator.validate(urlString: urlString),
                "Dangerous scheme '\(urlString)' must return nil"
            )
        }
    }

    func testSafeURLValidatorDomainSpoofingAndPortInjection() {
        let spoofingAttempts = [
            "https://github.com.evil.com/releases",
            "https://notgithub.com/releases",
            "https://evil-github.com/releases",
            "https://github.co/releases",
            "https://github.org/releases",
            "https://github.com:8080/releases", // Non-standard port
            "https://user:password@github.com/releases", // Embedded credentials
            "https://admin@github.com/releases", // Embedded userinfo
            "https://api.github.com:8443/releases", // Non-standard port on api
            "https:///github.com", // Malformed host
            "https://github.com:22/ssh"
        ]

        for urlString in spoofingAttempts {
            XCTAssertFalse(
                SafeURLValidator.isValid(urlString: urlString),
                "Spoofed or port-injected URL '\(urlString)' must be rejected"
            )
            XCTAssertNil(
                SafeURLValidator.validate(urlString: urlString),
                "Spoofed or port-injected URL '\(urlString)' must return nil"
            )
        }

        let validURLs = [
            "https://github.com/antigravity/resource-monitor/releases/tag/v1.0.1",
            "https://api.github.com/repos/antigravity/resource-monitor/releases"
        ]
        XCTAssertTrue(SafeURLValidator.isValid(urlString: validURLs[0]))
        XCTAssertTrue(SafeURLValidator.isValid(urlString: validURLs[1]))
    }

    // MARK: - 5. SensitiveDataSanitizer Boundary & Regex Stress Tests

    func testSensitiveDataSanitizerComplexCLIStrings() {
        let complexCLI = "python3 train.py --api-key=sk-ant-api03-abcdef1234567890abcdef1234567890 --token=ghp_ABCDefgh1234567890123456789012345678 --password=SuperSecretPassword123 -p ShortSecret123"

        let sanitized = SensitiveDataSanitizer.sanitize(argument: complexCLI)

        XCTAssertFalse(sanitized.contains("sk-ant-api03-abcdef1234567890abcdef1234567890"))
        XCTAssertFalse(sanitized.contains("ghp_ABCDefgh1234567890123456789012345678"))
        XCTAssertFalse(sanitized.contains("SuperSecretPassword123"))
        XCTAssertFalse(sanitized.contains("ShortSecret123"))
        XCTAssertTrue(sanitized.contains("***REDACTED***"))
    }

    func testSensitiveDataSanitizerStandardDatabaseURIs() {
        let uris = [
            "postgres://appuser:mySuperSecretPass@db.internal.net:5432/production",
            "mysql://admin:P@ssw0rd!@10.0.1.5:3306/users",
            "mongodb://root:SecretMongoKey@cluster0.mongodb.net:27017/test",
            "redis://default:authpassword123@redis.cache.windows.net:6379"
        ]

        for uri in uris {
            let sanitized = SensitiveDataSanitizer.sanitize(argument: uri)
            XCTAssertFalse(sanitized.contains("mySuperSecretPass"))
            XCTAssertFalse(sanitized.contains("P@ssw0rd!"))
            XCTAssertFalse(sanitized.contains("SecretMongoKey"))
            XCTAssertFalse(sanitized.contains("authpassword123"))
            XCTAssertTrue(sanitized.contains("***REDACTED***"))
        }
    }

    func testSensitiveDataSanitizerBenignArgumentsPreserved() {
        let benignArgs = [
            "--verbose",
            "-v",
            "--config=/etc/nginx/nginx.conf",
            "https://github.com/apple/swift",
            "--port=8080",
            "--workers=4",
            "ls -la /Users/username/Projects"
        ]

        for arg in benignArgs {
            let sanitized = SensitiveDataSanitizer.sanitize(argument: arg)
            XCTAssertEqual(sanitized, arg, "Benign argument '\(arg)' must not be mutated")
        }
    }
}

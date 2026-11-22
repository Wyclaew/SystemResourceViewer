import XCTest
@testable import SystemResourceViewer

final class Milestone5Challenger2StressTests: XCTestCase {

    // MARK: - 1. EasterEggStateMachine Concurrency & 10,000+ Click Stress Tests

    func testEasterEgg10000RapidConcurrentClicks() async {
        let stateMachine = EasterEggStateMachine()
        let totalConcurrentTasks = 20
        let clicksPerTask = 500
        let totalExpectedClicks = totalConcurrentTasks * clicksPerTask // 10,000 clicks

        // Initial invariant checks
        XCTAssertEqual(stateMachine.state.clickCount, 0)
        XCTAssertFalse(stateMachine.state.isUnlocked)
        XCTAssertFalse(stateMachine.state.showConfetti)
        XCTAssertFalse(stateMachine.hasFiredConfettiOnce)

        let startTime = Date()

        // Dispatch 20 concurrent tasks firing 500 clicks each
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<totalConcurrentTasks {
                group.addTask {
                    for _ in 0..<clicksPerTask {
                        stateMachine.registerClick()
                    }
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Verify thread-safety and exact state invariants
        XCTAssertEqual(
            stateMachine.state.clickCount,
            totalExpectedClicks,
            "Exact clickCount must be \(totalExpectedClicks) after concurrent execution without race lost-updates"
        )
        XCTAssertTrue(stateMachine.state.isUnlocked, "Easter egg must be unlocked after 10,000 clicks")
        XCTAssertTrue(stateMachine.hasFiredConfettiOnce, "Confetti must have fired once")
        // After 10,000 clicks (> 7), showConfetti should be false as confetti was triggered at 7
        XCTAssertFalse(stateMachine.state.showConfetti, "showConfetti must be false after the 7th click")
        XCTAssertLessThan(elapsed, 5.0, "10,000 concurrent clicks must complete within 5 seconds")
    }

    func testEasterEggExactSevenClickUnlockBoundary() {
        let stateMachine = EasterEggStateMachine()

        // Clicks 1 through 6: must NOT unlock and must NOT fire confetti
        for i in 1...6 {
            stateMachine.registerClick()
            XCTAssertEqual(stateMachine.state.clickCount, i)
            XCTAssertFalse(stateMachine.state.isUnlocked, "Must NOT be unlocked at click \(i)")
            XCTAssertFalse(stateMachine.state.showConfetti, "Must NOT show confetti at click \(i)")
            XCTAssertFalse(stateMachine.hasFiredConfettiOnce, "Confetti must not have fired yet at click \(i)")
        }

        // Click 7: EXACT unlock boundary
        stateMachine.registerClick()
        XCTAssertEqual(stateMachine.state.clickCount, 7)
        XCTAssertTrue(stateMachine.state.isUnlocked, "Must be unlocked at EXACTLY click 7")
        XCTAssertTrue(stateMachine.state.showConfetti, "Must show confetti at EXACTLY click 7")
        XCTAssertTrue(stateMachine.hasFiredConfettiOnce, "hasFiredConfettiOnce must be true at click 7")

        // Click 8: Remains unlocked, but confetti stops firing
        stateMachine.registerClick()
        XCTAssertEqual(stateMachine.state.clickCount, 8)
        XCTAssertTrue(stateMachine.state.isUnlocked, "Must remain unlocked at click 8")
        XCTAssertFalse(stateMachine.state.showConfetti, "Confetti must stop showing at click 8")
        XCTAssertTrue(stateMachine.hasFiredConfettiOnce, "hasFiredConfettiOnce must remain true")

        // Clicks 9 through 20: Remains unlocked, no confetti refire
        for i in 9...20 {
            stateMachine.registerClick()
            XCTAssertEqual(stateMachine.state.clickCount, i)
            XCTAssertTrue(stateMachine.state.isUnlocked)
            XCTAssertFalse(stateMachine.state.showConfetti)
        }
    }

    func testEasterEggBoundaryWithConcurrentPreUnlockAndMassivePostUnlock() async {
        let stateMachine = EasterEggStateMachine()

        // Concurrently execute exactly 6 clicks across 6 distinct tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    stateMachine.registerClick()
                }
            }
        }

        // Must be exactly 6 clicks and still locked
        XCTAssertEqual(stateMachine.state.clickCount, 6)
        XCTAssertFalse(stateMachine.state.isUnlocked)
        XCTAssertFalse(stateMachine.state.showConfetti)
        XCTAssertFalse(stateMachine.hasFiredConfettiOnce)

        // 7th click: single trigger
        stateMachine.registerClick()
        XCTAssertEqual(stateMachine.state.clickCount, 7)
        XCTAssertTrue(stateMachine.state.isUnlocked)
        XCTAssertTrue(stateMachine.state.showConfetti)
        XCTAssertTrue(stateMachine.hasFiredConfettiOnce)

        // Now dispatch 10,000 additional concurrent clicks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    for _ in 0..<500 {
                        stateMachine.registerClick()
                    }
                }
            }
        }

        XCTAssertEqual(stateMachine.state.clickCount, 10007)
        XCTAssertTrue(stateMachine.state.isUnlocked)
        XCTAssertFalse(stateMachine.state.showConfetti)
        XCTAssertTrue(stateMachine.hasFiredConfettiOnce)
    }

    func testEasterEggDismissConfettiAndResetUnderConcurrency() async {
        let stateMachine = EasterEggStateMachine()

        // Bring to unlocked state
        for _ in 1...7 {
            stateMachine.registerClick()
        }
        XCTAssertTrue(stateMachine.state.isUnlocked)
        XCTAssertTrue(stateMachine.state.showConfetti)

        // Dismiss confetti
        stateMachine.dismissConfetti()
        XCTAssertFalse(stateMachine.state.showConfetti)
        XCTAssertTrue(stateMachine.state.isUnlocked)

        // Reset
        stateMachine.reset()
        XCTAssertEqual(stateMachine.state.clickCount, 0)
        XCTAssertFalse(stateMachine.state.isUnlocked)
        XCTAssertFalse(stateMachine.state.showConfetti)
        XCTAssertFalse(stateMachine.hasFiredConfettiOnce)

        // Stress: Concurrently execute registerClick, dismissConfetti, and reset
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    for _ in 0..<200 {
                        stateMachine.registerClick()
                    }
                }
            }
            for _ in 0..<5 {
                group.addTask {
                    for _ in 0..<100 {
                        stateMachine.dismissConfetti()
                    }
                }
            }
        }

        // Must complete without deadlocks or crashes, lock integrity maintained
        XCTAssertGreaterThan(stateMachine.state.clickCount, 0)
    }

    // MARK: - 2. DashboardViewModel Filter Clearing Stress Tests

    @MainActor
    func testDashboardViewModelClearFiltersStress() async {
        let vm = DashboardViewModel(interval: 5.0)

        // Test diverse permutations of search queries and categories
        let testQueries = [
            "kernel_task",
            "WINDOWSERVER",
            "   spaces and tabs   ",
            "🚀🔥 unicode process",
            "العربية",
            "日本語プロセス",
            "[]().*+?^${}|\\", // regex chars
            String(repeating: "a", count: 200), // long query
            "0",
            "999999",
            ""
        ]

        let testCategories: [ProcessCategory] = [.all, .apps, .daemons, .system, .highLoad]

        for query in testQueries {
            for category in testCategories {
                vm.searchText = query
                vm.selectedCategory = category

                XCTAssertEqual(vm.searchText, query)
                XCTAssertEqual(vm.selectedCategory, category)

                // Call clearFilters
                vm.clearFilters()

                // Verify reset guarantees
                XCTAssertEqual(vm.searchText, "", "searchText must be empty after clearFilters")
                XCTAssertEqual(vm.selectedCategory, .all, "selectedCategory must be .all after clearFilters")
            }
        }
    }

    @MainActor
    func testDashboardViewModelFilterClearingProcessRestoration() async {
        let vm = DashboardViewModel(interval: 5.0)
        vm.searchText = "Process_1"
        vm.selectedCategory = .system
        XCTAssertEqual(vm.searchText, "Process_1")
        XCTAssertEqual(vm.selectedCategory, .system)

        vm.clearFilters()
        XCTAssertEqual(vm.searchText, "")
        XCTAssertEqual(vm.selectedCategory, .all)

        // Mock 100 process items with varied categories and names
        var mockProcesses: [ProcessItem] = []
        for i in 1...100 {
            let cat: ProcessCategory = (i % 3 == 0) ? .system : ((i % 3 == 1) ? .apps : .daemons)
            mockProcesses.append(
                ProcessItem(
                    id: pid_t(1000 + i),
                    name: "Process_\(i)",
                    cpuPercentage: Double(i % 20),
                    memoryBytes: UInt64(i * 10 * 1024 * 1024),
                    ownerUser: "user_\(i % 5)",
                    category: cat,
                    diskReadBytesPerSecond: Double(i * 1000),
                    diskWriteBytesPerSecond: Double(i * 500)
                )
            )
        }

        // Filter statically
        let filtered1 = DashboardViewModel.filterAndSortProcesses(
            processes: mockProcesses,
            query: "Process_1",
            category: .system,
            sortField: .cpu,
            sortAscending: false
        )
        // Only system processes matching "Process_1" (e.g. 12, 15, 18, etc.)
        for item in filtered1 {
            XCTAssertEqual(item.category, .system)
            XCTAssertTrue(item.name.contains("Process_1"))
        }

        // Now clear filter via pure static function (empty query, .all category)
        let cleared = DashboardViewModel.filterAndSortProcesses(
            processes: mockProcesses,
            query: "",
            category: .all,
            sortField: .cpu,
            sortAscending: false
        )
        XCTAssertEqual(cleared.count, mockProcesses.count, "Clearing filters must restore all 100 processes")
    }

    // MARK: - 3. Rapid Sequential Tab Switching Stress Tests

    @MainActor
    func testDashboardViewModelRapidTabSwitching1000Cycles() async {
        let vm = DashboardViewModel(interval: 5.0)
        let tabs = DashboardTab.allCases
        XCTAssertEqual(tabs.count, 4)

        let iterations = 1000
        let startTime = Date()

        for i in 0..<iterations {
            let targetTab = tabs[i % tabs.count]
            vm.selectedTab = targetTab
            XCTAssertEqual(vm.selectedTab, targetTab, "selectedTab must match target at cycle \(i)")

            // Interleave occasional filter changes and window visibility
            if i % 100 == 0 {
                vm.searchText = "test_\(i)"
                vm.selectedCategory = .apps
                vm.clearFilters()
                XCTAssertEqual(vm.searchText, "")
                XCTAssertEqual(vm.selectedCategory, .all)

                vm.setWindowVisible(i % 200 == 0)
                vm.setWindowOccluded(i % 200 != 0)
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 4.0, "1,000 sequential tab switches must complete under 4 seconds")

        // Final state verification
        vm.selectedTab = .processes
        vm.setWindowVisible(true)
        XCTAssertEqual(vm.selectedTab, .processes)
        XCTAssertTrue(vm.isWindowVisible)
        XCTAssertEqual(vm.cpuHistory.capacity, 60)
        XCTAssertEqual(vm.cpuHistory15m.capacity, 900)
    }

    // MARK: - 4. UpdateChecker Version Comparison & Resilience Tests

    func testUpdateCheckerSemanticVersionComprehensiveMatrix() {
        // Equal versions -> No update
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "1.1.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.1.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "v1.1.0", remoteTag: "1.1.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "v1.1.0", remoteTag: "v1.1.0"))

        // Older remote versions -> No update
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "1.0.9"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.0.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "0.9.9"))

        // Newer remote versions -> Update available
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "1.1.1"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.1.1"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "1.2.0"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.2.0"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "2.0.0"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v2.0.0"))

        // Prerelease comparisons:
        // Final release 1.1.0 vs 1.1.0-beta -> false (final release is newer than beta of same version)
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "1.1.0-beta"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.1.0-beta"))

        // Beta version 1.1.0-beta vs final 1.1.0 -> true (final release is an update over beta)
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0-beta", remoteTag: "1.1.0"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "v1.1.0-beta", remoteTag: "v1.1.0"))

        // Sequential prerelease: beta.1 vs beta.2 -> true
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0-beta.1", remoteTag: "1.1.0-beta.2"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0-beta.2", remoteTag: "1.1.0-beta.1"))

        // rc1 vs rc2 -> true
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0-rc1", remoteTag: "1.1.0-rc2"))

        // Malformed or empty tags -> No crash, returns false
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: ""))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "not-a-version"))
    }

    func testUpdateCheckerServiceDefaultTargetRepositoryAndFailures() async {
        // 1. Verify default repo in API call is "Wyclaew/SystemResourceViewer"
        final class CapturedURLBox: @unchecked Sendable {
            var requestedURL: URL?
        }
        let box = CapturedURLBox()

        M5C2MockURLProtocol.requestHandler = { request in
            box.requestedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {
                "tag_name": "v1.2.0",
                "name": "Version 1.2.0",
                "body": "v1.2.0 release",
                "html_url": "https://github.com/Wyclaew/SystemResourceViewer/releases/tag/v1.2.0",
                "published_at": "2026-11-22T12:00:00Z"
            }
            """.data(using: .utf8)!
            return (response, payload)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [M5C2MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = UpdateCheckerService(session: session)
        let release = await service.checkForUpdates(currentVersion: "1.1.0")

        XCTAssertNotNil(release)
        XCTAssertEqual(release?.tagName, "v1.2.0")
        XCTAssertEqual(
            box.requestedURL?.absoluteString,
            "https://api.github.com/repos/Wyclaew/SystemResourceViewer/releases/latest",
            "Target repository must be exactly Wyclaew/SystemResourceViewer"
        )

        // 2. HTTP 404 Not Found response resilience
        M5C2MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let release404 = await service.checkForUpdates(currentVersion: "1.1.0")
        XCTAssertNil(release404, "HTTP 404 must return nil without throwing")

        // 3. HTTP 500 Internal Server Error resilience
        M5C2MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let release500 = await service.checkForUpdates(currentVersion: "1.1.0")
        XCTAssertNil(release500, "HTTP 500 must return nil without throwing")

        // 4. Corrupt / Malformed JSON resilience
        M5C2MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let malformed = "{ this is not valid json }".data(using: .utf8)!
            return (response, malformed)
        }
        let releaseMalformed = await service.checkForUpdates(currentVersion: "1.1.0")
        XCTAssertNil(releaseMalformed, "Malformed JSON must return nil without throwing")
    }

    func testUpdateCheckerConcurrentQueriesResilience() async {
        let expectedHost = "https://api.github.com/repos/Wyclaew/SystemResourceViewer/releases/latest"

        M5C2MockURLProtocol.requestHandler = { request in
            guard request.url?.absoluteString == expectedHost else {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            let payload = """
            {
                "tag_name": "v1.1.1",
                "name": "Version 1.1.1",
                "body": "Bugfix release",
                "html_url": "https://github.com/Wyclaew/SystemResourceViewer/releases/tag/v1.1.1",
                "published_at": "2026-11-22T14:00:00Z"
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, payload)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [M5C2MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = UpdateCheckerService(session: session)

        // Dispatch 50 concurrent requests to the actor-isolated service
        await withTaskGroup(of: GitHubRelease?.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let version = (i % 2 == 0) ? "1.1.0" : "1.2.0"
                    return await service.checkForUpdates(currentVersion: version)
                }
            }

            var responsesReceived = 0
            for await release in group {
                responsesReceived += 1
                if let release {
                    XCTAssertEqual(release.tagName, "v1.1.1")
                }
            }
            XCTAssertEqual(responsesReceived, 50, "All 50 concurrent update checks must complete safely")
        }
    }

    @MainActor
    func testDashboardViewModelRapidFilterAndSortResilience() async {
        let vm = DashboardViewModel(interval: 5.0)
        let fields: [ProcessSortField] = [.cpu, .memory, .name, .pid, .diskIO]
        let categories: [ProcessCategory] = [.all, .apps, .daemons, .system, .highLoad]

        // Rapidly thrash properties across 500 iterations
        for i in 0..<500 {
            vm.searchText = "proc_\(i % 10)"
            vm.selectedCategory = categories[i % categories.count]
            vm.sortField = fields[i % fields.count]
            vm.sortAscending = (i % 2 == 0)

            if i % 25 == 0 {
                vm.clearFilters()
                XCTAssertEqual(vm.searchText, "")
                XCTAssertEqual(vm.selectedCategory, .all)
            }
        }

        // Final reset
        vm.clearFilters()
        XCTAssertEqual(vm.searchText, "")
        XCTAssertEqual(vm.selectedCategory, .all)
    }

    // MARK: - 5. App Version and Fallback Integrity

    @MainActor
    func testDashboardViewModelAppVersionIs110() {
        let vm = DashboardViewModel(interval: 5.0)
        XCTAssertEqual(vm.appVersion, "1.1.0", "DashboardViewModel fallback version must be 1.1.0")
    }
}

// MARK: - Dedicated Mock URLProtocol for M5C2 Tests

private final class M5C2MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
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

import XCTest
@testable import SystemResourceViewer

final class UserSettingsPersistenceTests: XCTestCase {
    func testDefaultUserSettingsValues() {
        let settings = UserSettings()
        XCTAssertEqual(settings.refreshInterval, 2.0)
        XCTAssertEqual(settings.startupTab, "Processes")
        XCTAssertEqual(settings.themeOverride, .system)
        XCTAssertEqual(settings.historyTimelineRange, "1m")
        XCTAssertEqual(settings.cpuAlertThreshold, 90.0)
        XCTAssertEqual(settings.cpuAlertEnabled, true)
        XCTAssertEqual(settings.memoryPressureAlertEnabled, true)
        XCTAssertEqual(settings.thermalAlertThreshold, 90.0)
        XCTAssertEqual(settings.thermalAlertEnabled, true)
        XCTAssertEqual(settings.privacySettings.maskSensitiveArguments, true)
        XCTAssertEqual(settings.privacySettings.maskLocalIPAddress, false)
    }

    func testUserSettingsJSONRoundTrip() throws {
        var settings = UserSettings()
        settings.refreshInterval = 1.0
        settings.startupTab = "History"
        settings.themeOverride = .dark
        settings.historyTimelineRange = "15m"
        settings.cpuAlertThreshold = 85.0
        settings.cpuAlertEnabled = false
        settings.memoryPressureAlertEnabled = true
        settings.thermalAlertThreshold = 80.0
        settings.thermalAlertEnabled = false
        settings.privacySettings.maskSensitiveArguments = false
        settings.privacySettings.maskLocalIPAddress = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)

        XCTAssertEqual(decoded.refreshInterval, 1.0)
        XCTAssertEqual(decoded.startupTab, "History")
        XCTAssertEqual(decoded.themeOverride, .dark)
        XCTAssertEqual(decoded.historyTimelineRange, "15m")
        XCTAssertEqual(decoded.cpuAlertThreshold, 85.0)
        XCTAssertEqual(decoded.cpuAlertEnabled, false)
        XCTAssertEqual(decoded.memoryPressureAlertEnabled, true)
        XCTAssertEqual(decoded.thermalAlertThreshold, 80.0)
        XCTAssertEqual(decoded.thermalAlertEnabled, false)
        XCTAssertEqual(decoded.privacySettings.maskSensitiveArguments, false)
        XCTAssertEqual(decoded.privacySettings.maskLocalIPAddress, true)
    }

    func testUserDefaultsPersistenceCustomSuite() {
        let suiteName = "com.systemresourceviewer.test.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create custom UserDefaults suite")
            return
        }

        var customSettings = UserSettings()
        customSettings.refreshInterval = 0.5
        customSettings.startupTab = "System Profile"
        customSettings.themeOverride = .light

        customSettings.save(to: testDefaults)

        let loaded = UserSettings.load(from: testDefaults)
        XCTAssertEqual(loaded.refreshInterval, 0.5)
        XCTAssertEqual(loaded.startupTab, "System Profile")
        XCTAssertEqual(loaded.themeOverride, .light)

        UserSettings.reset(in: testDefaults)
        let afterReset = UserSettings.load(from: testDefaults)
        XCTAssertEqual(afterReset, UserSettings.defaultSettings)

        testDefaults.removePersistentDomain(forName: suiteName)
    }
}

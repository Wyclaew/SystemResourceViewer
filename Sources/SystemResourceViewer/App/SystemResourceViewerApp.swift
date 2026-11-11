import AppKit
import SwiftUI

/// App Delegate to configure standard macOS application policy and window activation.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.title == "Resource Monitor" || window.identifier?.rawValue.contains("main-window") == true {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }
}

/// Main application entry point providing the primary dashboard window and menu bar extra.
@main
struct SystemResourceViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = DashboardViewModel()
    @Environment(\.openWindow) private var openWindow

    public init() {
        if CommandLine.arguments.contains("--smoke-test") {
            Task {
                print("=== ResourceMonitor Smoke Test ===")
                let scheduler = MetricsScheduler(interval: 1.0)
                let stream = await scheduler.metricsStream()
                var count = 0
                for await snapshot in stream {
                    count += 1
                    print("--- Snapshot #\(count) ---")
                    print("CPU: \(String(format: "%.1f%%", snapshot.cpu.totalUsage)) | P-Cores: \(snapshot.cpu.pCoreCount), E-Cores: \(snapshot.cpu.eCoreCount)")
                    print("RAM: \(Formatters.formatBytes(snapshot.memory.usedBytes)) / \(Formatters.formatBytes(snapshot.memory.totalBytes)) (\(Formatters.formatPercentage(snapshot.memory.usedPercentage)))")
                    print("Active Processes: \(snapshot.processes.count)")
                    if count >= 2 {
                        print("=== Smoke Test Passed Successfully ===")
                        exit(0)
                    }
                }
            }
        }
    }

    var body: some Scene {
        // Main Primary Diagnostic Window
        Window("Resource Monitor", id: "main-window") {
            DashboardWindowView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 600)

        // Menu Bar Companion
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel) {
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

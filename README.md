# Resource Monitor (PulseCore)

A production-grade, ultra-lightweight macOS System Resource Monitor application architected in **Swift 6** and **SwiftUI**, targeting **macOS 14 (Sonoma)** and later, engineered specifically for **Apple Silicon** architecture.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-teal)
![Footprint](https://img.shields.io/badge/CPU%20Footprint-%3C%201%25-green)
![RAM Footprint](https://img.shields.io/badge/RAM%20Footprint-%3C%2025%20MB-green)
![License](https://img.shields.io/badge/License-MIT-lightgrey)

---

## Overview

**Resource Monitor** provides real-time, low-overhead hardware telemetry for macOS. Built from the ground up to take advantage of Apple Silicon's unified memory and asymmetric core topologies, it delivers comprehensive diagnostic metrics directly through an elegant macOS Menu Bar interface and an expandable multi-section Diagnostics Dashboard.

---

## System Architecture & Module Design

Resource Monitor is structured in four decoupled, actor-isolated layers strictly adhering to **Swift 6 complete concurrency**:

```
Sources/SystemResourceViewer/
├── App/
│   └── SystemResourceViewerApp.swift        # App entry point (MenuBarExtra & Dashboard Window)
├── Core/
│   ├── Bridging/
│   │   ├── DarwinMachBridge.swift           # Mach host stats, CPU topology, VM stats, libproc
│   │   ├── IOKitBridge.swift                # Block storage I/O, AppleSmartBattery, IOAccelerator
│   │   └── IOHIDBridge.swift                # IOHIDEventSystemClient thermal sensors
│   ├── Engine/
│   │   ├── MetricsScheduler.swift           # Adaptive dual-mode polling engine (< 1% CPU idle)
│   │   └── Formatters.swift                 # High-performance string & byte formatters
│   └── Services/
│       ├── CPUMonitorService.swift          # Core-by-core P/E load calculation
│       ├── GPUMonitorService.swift          # Device, renderer, tiler % and VRAM metrics
│       ├── ThermalMonitorService.swift      # SoC die temps, battery/NAND temps & fan tachometer
│       ├── MemoryMonitorService.swift       # VM memory pressure, swap, active/wired/compressed
│       ├── DiskAndPowerService.swift        # Storage capacity, disk throughput & battery wattage
│       ├── NetworkMonitorService.swift      # Network throughput & TCP socket latency probe
│       ├── ProcessMonitorService.swift      # Process sampling, category filtering & Rosetta 2 badge
│       ├── ProcessAction.swift              # Safe POSIX signal delivery with error handling
│       └── UpdateCheckerService.swift       # GitHub Releases API query and semver comparison
├── Models/
│   ├── CPUMetrics.swift                     # Core topology and load snapshots
│   ├── GPUMetrics.swift                     # GPU utilization and VRAM allocation model
│   ├── ThermalMetrics.swift                 # Thermal state, temperatures and fan speed models
│   ├── MemoryMetrics.swift                  # Memory pages, swap, and pressure levels
│   ├── DiskMetrics.swift                    # Storage capacity and throughput model
│   ├── NetworkMetrics.swift                 # Bandwidth and latency models
│   ├── PowerMetrics.swift                   # Battery wattage, condition, and adapter telemetry
│   ├── ProcessItem.swift                    # Sendable process metadata with category & architecture
│   ├── SystemMetrics.swift                  # Unified telemetry snapshot
│   └── UpdateMetrics.swift                  # GitHub Release metadata & version models
├── ViewModels/
│   └── DashboardViewModel.swift             # @MainActor coordinator and 60-second rolling history
└── Views/
    ├── Components/
    │   ├── AdaptiveColor.swift              # Dynamic semantic color palette
    │   ├── AuthorBadgeView.swift            # "WycDev" author branding & Easter egg trigger
    │   ├── CardContainer.swift              # UltraThinMaterial frosted card container
    │   ├── ConfettiView.swift               # Celebratory confetti particle burst
    │   ├── CoreUsageBarView.swift           # Horizontal P/E core load bars
    │   ├── MetricRingGauge.swift            # Circular ring gauge with gradient fills
    │   ├── MetricSparklineView.swift        # 60-second Swift Charts sparkline
    │   └── ProcessRowView.swift             # Process row with category badges & action buttons
    ├── Dashboard/
    │   ├── DashboardWindowView.swift        # Multi-section diagnostics dashboard
    │   ├── CPUDashboardSection.swift        # Processor topology and core telemetry
    │   ├── GPUDashboardSection.swift        # GPU device/renderer/tiler load and VRAM
    │   ├── ThermalDashboardSection.swift    # SoC temperatures, thermal state & fan RPM
    │   ├── MemoryDashboardSection.swift     # RAM pages, swap, and pressure gauge
    │   ├── DiskDashboardSection.swift       # Storage capacity and read/write speeds
    │   ├── NetworkDashboardSection.swift    # Bandwidth sparklines and socket ping
    │   └── PowerDashboardSection.swift      # Battery health, wattage & power source
    └── MenuBar/
        ├── MenuBarLabelView.swift           # Menu bar live readout
        └── MenuBarPopoverView.swift         # Quick-glance menu bar popover
```

### Architectural Highlights

1. **Zero Subprocess Overhead**: The application operates entirely via in-process Darwin C APIs (`host_processor_info`, `host_statistics64`, `proc_pidinfo`, `getifaddrs`) and IOKit frameworks (`IOBlockStorageDriver`, `IOPMCopyPowerSourcesInfo`, `IOAccelerator`, `IOHIDEventSystemClient`). It never spawns heavy shell subprocesses (`top`, `ps`, `vm_stat`), ensuring sub-millisecond query execution.
2. **Adaptive Dual-Mode Scheduling**: The `MetricsScheduler` automatically alternates between `.minimal` mode (when the dashboard window and popover are hidden) and `.full` mode (when viewing telemetry). In `.minimal` mode, expensive operations such as process table iteration and detailed core profiling are paused, reducing CPU usage to `< 1%`.
3. **Actor-Isolated Telemetry Workers**: All telemetry sampling services are declared as Swift `actor` types, ensuring thread safety and data-race freedom under Swift 6 strict concurrency checks (`-strict-concurrency=complete`).

---

## Comprehensive Telemetry Features

### 1. CPU Performance & Topology
- **P-Core & E-Core Breakdown**: Automatically discovers Apple Silicon hybrid core topology via `sysctl` (`hw.nperflevels`, `hw.perflevel0.logicalcpu`, `hw.perflevel1.logicalcpu`).
- **Individual Core Load**: Visual horizontal usage bars for every logical core, categorizing Performance Cores vs. Efficiency Cores.
- **System, User, & Idle Metrics**: Delta-based Mach processor tick analysis providing accurate aggregate utilization.

### 2. GPU Utilization & VRAM Telemetry
- **Device, Renderer, & Tiler Utilization**: Live GPU load metrics queried directly from IOKit `IOAccelerator` device statistics.
- **Unified VRAM Allocation**: Real-time allocated VRAM and in-use VRAM tracking.
- **Hardware Metadata**: Displays GPU model name and hardware core count.

### 3. Apple Silicon Thermal & Fan Monitoring
- **SoC Die & Peripheral Temperatures**: Multi-channel thermal readouts via `IOHIDEventSystemClient` covering SoC compute dies, battery, and NAND storage.
- **Thermal Pressure State**: Live macOS thermal throttling state indicator (Nominal, Fair, Serious, Critical).
- **Fan Tachometer & Passive Cooling**: Hardware fan speed in RPM for fan-equipped Macs (MacBook Pro, Mac Studio, Mac mini), with automatic fallback to a dynamic passive-cooling display on fanless architectures (MacBook Air).

### 4. RAM & Memory Pressure
- **macOS VM Statistics**: Real-time breakdown of Active, Wired, Compressed, and Free memory pages.
- **Swap Memory Tracking**: Live monitoring of swap file usage.
- **Memory Pressure Gauge**: Color-coded circular gauge reflecting system memory pressure states (Normal, Warning, Critical) via `host_statistics64`.

### 5. Storage & Disk Throughput
- **Volume Metrics**: Total capacity, used space, and free space for mounted APFS/HFS+ volumes.
- **Live Disk I/O**: Real-time read and write throughput (MB/s) computed from block storage driver byte deltas.

### 6. Network Bandwidth & Latency
- **Real-Time Bandwidth**: Live upload and download throughput (KB/s, MB/s) queried through network interface address structures (`getifaddrs`).
- **Active Interface Detection**: Displays primary interface type (Wi-Fi, Ethernet, Thunderbolt).
- **Socket Latency Probe**: Non-intrusive background TCP socket ping probe to public DNS resolver displaying live latency in milliseconds.

### 7. Battery & Power Telemetry
- **Battery Status**: Percentage charge, charging/discharging state, cycle count, and battery health condition via `IOPMCopyPowerSourcesInfo`.
- **Power Wattage**: Real-time charge or discharge rate in Watts (W) and AC adapter connection status.

### 8. Process Filtering & Lifecycle Management
- **Search & Category Pills**: Search processes by name or PID, with quick filter pills:
  - **All**: Complete system process table.
  - **Apps**: Foreground graphical user applications (`/Applications`).
  - **Daemons**: Background daemons and launch agents.
  - **System**: Kernel and root-level system services.
  - **High Load**: Processes consuming significant CPU (> 5%) or memory (> 200 MB).
- **Architecture Badging**: Distinguishes native Apple Silicon (`arm64`) from translated (`Rosetta 2 x86_64`) processes.
- **Process Metadata**: Displays thread counts and owner usernames (`proc_pidinfo` and Mach UID mapping).
- **Per-Process Disk I/O**: Real-time read and write throughput per process calculated via Mach `proc_pid_rusage(RUSAGE_INFO_V4)` delta rates.
- **Process Execution Control**: Pause (`SIGSTOP`) and resume (`SIGCONT`) capabilities with live "Paused" state indicator badges.
- **Deep Process Inspector**: Comprehensive inspection sheet displaying thread breakdown, open file descriptors via `PROC_PIDLISTFDS`, Mach VM virtual/resident/compressed pages, and context switch counters.
- **Safe POSIX Process Termination**: Safe `SIGTERM` termination and force-kill `SIGKILL` controls with destructive action confirmation dialogs, system process protection guards (`ProcessGuard` daemon blacklist protecting `kernel_task`, `launchd`, `WindowServer`, `loginwindow`, PID <= 1), and actionable error alerts.

### 9. Multi-Tab Interface & System Profile
- **Four Dedicated Tabs**:
  - **Processes**: High-performance sortable table with memory, CPU, disk I/O, pause/resume, and inspect controls.
  - **Diagnostics**: Real-time hardware gauges, CPU topology, GPU utilization, and thermal sensors.
  - **History**: Multi-timeline rolling telemetry charts (1m, 5m, 15m intervals) with min, mean, and max statistical analysis.
  - **System Profile**: Detailed hardware inventory including Mac marketing model name, Apple Silicon chip generation, CPU P/E core topology, macOS version and build number, boot time, and system uptime.

### 10. Resource Alerts & Diagnostics Export
- **Proactive Resource Alerts**: Configurable warning thresholds for sustained high CPU utilization, elevated memory pressure, and thermal throttling conditions.
- **Multi-Format Telemetry Export**: Export diagnostic reports in RFC 4180-compliant CSV, structured JSON snapshot, or Markdown formats.
- **Privacy & Redaction Controls**: Configurable IP address masking, credential redaction, and username obfuscation during export and network display.

### 11. GitHub Release Update Checker
- **Automated Version Checking**: Periodically checks the GitHub Releases API for newer version tags.
- **Semantic Versioning Comparison**: Robust parsing and comparison of major, minor, patch, and prerelease identifiers.
- **Update Confirmation Dialog**: Prompts user with release notes and requires interactive confirmation before redirecting to the release download page.

### 12. Author Easter Egg ("WycDev")
- **Status Bar Branding**: Displays "WycDev" branding in the status bar corner.
- **7-Click Secret Reveal**: Clicking the author label 7 times unlocks adjacent heart (`heart.fill`) and cat (`cat.fill`) SF Symbols.
- **Celebratory Confetti Animation**: Triggers a self-terminating 3-second celebratory confetti particle burst upon the first 7-click activation, returning to 0% idle CPU overhead upon completion.

---

## macOS Gatekeeper Installation Guide

Because **Resource Monitor** is distributed independently as an open-source project and is not signed with a paid Apple Developer certificate, macOS Gatekeeper may display a security alert when you first open the application:

> *"Resource Monitor is damaged and can't be opened. You should move it to the Trash."*  
> or  
> *"macOS cannot verify that this app is free from malware."*

This is standard macOS security behavior for unsigned apps downloaded from the internet. Choose any of the three methods below to grant permission:

### Method 1: The Finder Right-Click Bypass (Recommended GUI Method)

1. Open `Resource Monitor.dmg` and drag `Resource Monitor.app` into your `/Applications` folder.
2. Open Finder and navigate to `/Applications`.
3. **Right-click** (or hold **Control** and click) on **`Resource Monitor.app`**.
4. Click **Open** from the context menu.
5. A confirmation dialog will appear stating that macOS cannot verify the developer. Click **Open**.
6. macOS creates a permanent security whitelist exception for the application. Subsequent launches from Spotlight, Launchpad, or the Dock will open immediately without warnings.

### Method 2: System Settings "Open Anyway" (macOS Ventura, Sonoma & Sequoia)

1. Double-click `Resource Monitor.app` in `/Applications`. If blocked by a warning dialog, click **Cancel** or **Done**.
2. Open **System Settings** on your Mac.
3. In the sidebar, select **Privacy & Security**.
4. Scroll down to the **Security** section.
5. You will see a message: *"Resource Monitor was blocked from use because it is not from an identified developer."*
6. Click **Open Anyway**.
7. Enter your Mac administrator password or use Touch ID, then click **Open**.

### Method 3: Instant Terminal Command (CLI Method)

If you prefer using the Terminal, you can remove the macOS quarantine flag with a single command:

```bash
# Remove the quarantine extended attribute recursively:
xattr -cr "/Applications/Resource Monitor.app"
```

Or specifically remove only the quarantine attribute:

```bash
xattr -d com.apple.quarantine "/Applications/Resource Monitor.app"
```

If the signature was invalidated during custom binary modifications, you can apply a fresh ad-hoc code signature:

```bash
codesign --force --deep --sign - "/Applications/Resource Monitor.app"
```

---

## Build and Test Instructions

### Prerequisites
- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ or Command Line Tools with Swift 6.0 toolchain

### 1. Build from Source
```bash
# Debug build:
swift build

# Production release build with Swift 6 strict concurrency:
swift build -c release -Xswiftc -strict-concurrency=complete
```

### 2. Run Automated Test Suite
Execute the comprehensive automated test suite (314 unit, boundary, optimization, and security stress tests):
```bash
swift test
```

### 3. Package Installable DMG (`build_app.sh`)
Build the release binary, assemble `Resource Monitor.app`, ad-hoc sign the bundle, and package a compressed `.dmg` disk image with an `/Applications` symlink:
```bash
chmod +x build_app.sh
./build_app.sh
```
The script will output `Resource Monitor.dmg` in the repository root and verify its integrity and mountability.

### 4. Direct Local Installation (`install.sh`)
Compile and install the application directly into `~/Applications`:
```bash
chmod +x install.sh
./install.sh
```

---

## CI/CD Release Automation

The repository includes a fully automated GitHub Actions release workflow located at `.github/workflows/release.yml`:

- **Triggers**: Automatically runs on push to `main` / `master` and version tag pushes (`v*`).
- **Runner**: Executes on `macos-14` (Apple Silicon M1 runner).
- **Workflow Pipeline**:
  1. Checks out repository code.
  2. Runs `swift test` to ensure all 314 tests pass.
  3. Executes `./build_app.sh` to compile the release binary and generate `Resource Monitor.dmg`.
  4. Automatically prunes previous GitHub releases and outdated git tags using the GitHub CLI (`gh`).
  5. Publishes a new GitHub release with `Resource Monitor.dmg` attached as a downloadable asset.

---

## License

This project is licensed under the MIT License. See the repository for details.

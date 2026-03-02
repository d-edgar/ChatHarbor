import Foundation
import Cocoa
import Combine
import CoreGraphics

/// Detects when the user's screen is being shared, recorded, or
/// remotely viewed. Uses multiple detection signals:
///   1. Running app inspection (known screen sharing bundle IDs)
///   2. CGWindow list inspection (sharing agents, system indicators)
///   3. CoreGraphics display mirroring detection (AirPlay, Sidecar, etc.)
///   4. Manual toggle via keyboard shortcut (for browser-based sharing)
///
/// The detector runs a lightweight background timer (every 2 seconds)
/// and publishes changes via `@Published isScreenBeingShared`.
@MainActor
final class ScreenShareDetector: ObservableObject {

    static let shared = ScreenShareDetector()

    /// Whether screen sharing/recording is currently detected (auto or manual)
    @Published var isScreenBeingShared: Bool = false

    /// Whether the user has manually engaged the shield (via keyboard shortcut)
    @Published var isManuallyEngaged: Bool = false

    /// Human-readable reason for the current detection (for debugging)
    @Published var detectionReason: String = ""

    /// Clean, user-facing name of the app/service that triggered detection
    @Published var detectedAppName: String = ""

    private var pollTimer: Timer?

    // MARK: - Known App Lists

    /// Bundle identifiers of known screen sharing / recording apps.
    private static let screenShareBundleIds: Set<String> = [
        // Video conferencing (screen share mode)
        "us.zoom.xos",                         // Zoom
        "com.microsoft.teams",                  // Microsoft Teams
        "com.microsoft.teams2",                 // Microsoft Teams (new)
        "com.cisco.webexmeetingsapp",           // Webex
        "com.google.Chrome.app.kjgfgldnnfobanl", // Google Meet (PWA)
        "com.skype.skype",                     // Skype
        "com.apple.FaceTime",                  // FaceTime

        // Chat apps with screen sharing
        "com.hnc.Discord",                     // Discord
        "com.tinyspeck.slackmacgap",           // Slack

        // Screen recording / capture tools
        "com.apple.QuickTimePlayerX",           // QuickTime screen recording
        "com.loom.desktop",                     // Loom
        "com.getcleanshot.app",                 // CleanShot X
        "com.techsmith.camtasia",               // Camtasia
        "com.obsproject.obs-studio",            // OBS Studio
        "com.techsmith.snagit",                // Snagit
        "com.kap.Kap",                         // Kap
        "com.screenflow.ScreenFlow",           // ScreenFlow

        // Remote desktop / screen sharing
        "com.teamviewer.TeamViewer",            // TeamViewer
        "com.anydesk.anydesk",                  // AnyDesk
        "com.realvnc.vncviewer",               // VNC Viewer
        "com.parallels.access.server",          // Parallels Access
        "com.apple.ScreenSharing",              // macOS Screen Sharing
    ]

    /// Apps that persist in the background — only flag these when they
    /// have visible on-screen windows (indicating active sharing/capture).
    private static let requiresWindowCheckBundleIds: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.cisco.webexmeetingsapp",
        "com.skype.skype",
        "com.apple.FaceTime",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
    ]

    /// Process names to check (for apps that may not have consistent bundle IDs)
    private static let screenShareProcessNames: Set<String> = [
        "ScreenSharingAgent",
        "screensharingd",
    ]

    private init() {}

    // MARK: - Public API

    /// Start polling for screen share status. Call when the feature is enabled.
    func startMonitoring() {
        guard pollTimer == nil else { return }

        // Do an initial check immediately
        updateStatus()

        // Poll every 2 seconds — lightweight enough to be negligible
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatus()
            }
        }
    }

    /// Stop polling. Call when the feature is disabled.
    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        isScreenBeingShared = false
        isManuallyEngaged = false
    }

    /// Toggle the manual shield engagement (for browser-based sharing
    /// that can't be detected automatically).
    func toggleManualEngagement() {
        isManuallyEngaged.toggle()
        if isManuallyEngaged {
            detectionReason = "Manually engaged via keyboard shortcut"
            detectedAppName = "Manual"
            isScreenBeingShared = true
        } else {
            // Re-check auto detection — if something is still sharing,
            // keep the shield up
            updateStatus()
        }
    }

    // MARK: - Detection Logic

    private func updateStatus() {
        let autoDetected = checkForScreenCapture()

        if isManuallyEngaged {
            // Manual override — always show shield
            isScreenBeingShared = true
        } else if autoDetected != isScreenBeingShared {
            isScreenBeingShared = autoDetected
        }
    }

    /// Detection result containing both debug and user-facing info
    private struct DetectionResult {
        let debugReason: String
        let appName: String
    }

    /// Combines multiple signals to determine if the screen is being captured.
    private func checkForScreenCapture() -> Bool {
        // Signal 1: Check if any known screen sharing apps are running
        if let result = checkRunningApps() {
            detectionReason = result.debugReason
            detectedAppName = result.appName
            return true
        }

        // Signal 2: Check the CGWindow list for screen sharing agents
        if let result = checkWindowList() {
            detectionReason = result.debugReason
            detectedAppName = result.appName
            return true
        }

        // Signal 3: Check for active display mirroring (AirPlay, Sidecar, etc.)
        if let result = checkDisplayMirroring() {
            detectionReason = result.debugReason
            detectedAppName = result.appName
            return true
        }

        if !isManuallyEngaged {
            detectionReason = ""
            detectedAppName = ""
        }
        return false
    }

    // MARK: - Signal 1: Running Applications

    /// Check if any known screen sharing / recording apps are actively running.
    private func checkRunningApps() -> DetectionResult? {
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            if let bundleId = app.bundleIdentifier,
               Self.screenShareBundleIds.contains(bundleId) {
                let appName = app.localizedName ?? bundleId

                // Some apps persist in the background — only flag them
                // if they have a visible on-screen window
                if Self.requiresWindowCheckBundleIds.contains(bundleId) {
                    if hasOnScreenWindows(pid: app.processIdentifier) {
                        return DetectionResult(
                            debugReason: "App: \(appName) (\(bundleId)) — has on-screen windows",
                            appName: appName
                        )
                    }
                } else {
                    // Dedicated screen recording / remote desktop apps — running = capturing
                    return DetectionResult(
                        debugReason: "App: \(appName) (\(bundleId)) — running",
                        appName: appName
                    )
                }
            }

            // Check process names for system-level sharing agents
            if let name = app.localizedName,
               Self.screenShareProcessNames.contains(name) {
                return DetectionResult(
                    debugReason: "Process: \(name) (pid \(app.processIdentifier))",
                    appName: name
                )
            }
        }

        return nil
    }

    /// Check if a process has visible on-screen windows (indicates active use).
    private func hasOnScreenWindows(pid: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        return windowList.contains { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { return false }
            return ownerPID == pid
        }
    }

    // MARK: - Signal 2: Window List (Sharing Agents)

    /// Check the system window list for screen sharing agent windows.
    private func checkWindowList() -> DetectionResult? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in windowList {
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let windowName = info[kCGWindowName as String] as? String ?? ""
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0

            // macOS screen sharing agents (incoming remote viewers)
            if ownerName == "ScreenSharingAgent" || ownerName == "screensharingd" {
                return DetectionResult(
                    debugReason: "Window: \(ownerName) (pid \(ownerPID))",
                    appName: "Screen Sharing"
                )
            }

            // Built-in macOS Screen Sharing app
            if ownerName == "Screen Sharing" || windowName.contains("Screen Sharing") {
                return DetectionResult(
                    debugReason: "Window: \(ownerName) — \"\(windowName)\" (pid \(ownerPID))",
                    appName: "Screen Sharing"
                )
            }
        }

        return nil
    }

    // MARK: - Signal 3: Display Mirroring (AirPlay / Sidecar)

    /// Check if any display is currently in a mirror set, which indicates
    /// active AirPlay mirroring, Sidecar mirroring, or physical display mirroring.
    /// This is the most reliable way to detect AirPlay screen mirroring because
    /// it reflects real-time state — true only while actively mirroring.
    private func checkDisplayMirroring() -> DetectionResult? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else {
            return nil
        }

        for display in displays {
            let mirrorOf = CGDisplayMirrorsDisplay(display)
            if mirrorOf != kCGNullDirectDisplay {
                return DetectionResult(
                    debugReason: "Display \(display) is mirroring display \(mirrorOf)",
                    appName: "Screen Mirroring"
                )
            }
        }

        return nil
    }
}

import Foundation
import Cocoa
import Combine
import CoreGraphics

/// Detects when the user's screen is being shared, recorded, or
/// remotely viewed. Uses CoreGraphics window list polling and
/// running-app inspection to identify screen capture activity.
///
/// The detector runs a lightweight background timer (every 2 seconds)
/// and publishes changes via `@Published isScreenBeingShared`.
@MainActor
final class ScreenShareDetector: ObservableObject {

    static let shared = ScreenShareDetector()

    /// Whether screen sharing/recording is currently detected
    @Published var isScreenBeingShared: Bool = false

    private var pollTimer: Timer?

    /// Bundle identifiers of known screen sharing / recording apps.
    /// When any of these are running AND actively capturing, we trigger.
    private static let screenShareBundleIds: Set<String> = [
        // Video conferencing (screen share mode)
        "us.zoom.xos",                         // Zoom
        "com.microsoft.teams",                  // Microsoft Teams
        "com.microsoft.teams2",                 // Microsoft Teams (new)
        "com.cisco.webexmeetingsapp",           // Webex
        "com.google.Chrome.app.kjgfgldnnfobanl", // Google Meet (PWA)

        // Screen recording / capture tools
        "com.apple.screencaptureui",            // macOS Screenshot/Record
        "com.apple.QuickTimePlayerX",           // QuickTime screen recording
        "com.loom.desktop",                     // Loom
        "com.getcleanshot.app",                 // CleanShot X
        "com.techsmith.camtasia",               // Camtasia

        // Remote desktop / screen sharing
        "com.teamviewer.TeamViewer",            // TeamViewer
        "com.anydesk.anydesk",                  // AnyDesk
        "com.realvnc.vncviewer",               // VNC Viewer
        "com.parallels.access.server",          // Parallels Access
    ]

    /// Process names to check (for apps that may not have consistent bundle IDs)
    private static let screenShareProcessNames: Set<String> = [
        "screencaptureui",
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
    }

    // MARK: - Detection Logic

    private func updateStatus() {
        let detected = checkForScreenCapture()
        if detected != isScreenBeingShared {
            isScreenBeingShared = detected
        }
    }

    /// Combines multiple signals to determine if the screen is being captured.
    private func checkForScreenCapture() -> Bool {
        // Signal 1: Check if any known screen sharing apps are running
        if checkRunningApps() { return true }

        // Signal 2: Check the CGWindow list for screen recording indicators
        if checkWindowList() { return true }

        return false
    }

    /// Check if any known screen sharing / recording apps are actively running.
    private func checkRunningApps() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            // Check bundle identifiers
            if let bundleId = app.bundleIdentifier,
               Self.screenShareBundleIds.contains(bundleId) {
                // For video conferencing apps, they're always running —
                // we only flag them if they have an active window (suggesting
                // an active call / share session)
                if isConferencingApp(bundleId) {
                    if app.isActive || !app.isHidden {
                        // Additional check: see if they have on-screen windows
                        if hasOnScreenWindows(pid: app.processIdentifier) {
                            return true
                        }
                    }
                } else {
                    // Screen recording / remote desktop apps — running = capturing
                    return true
                }
            }

            // Check process names for system-level sharing agents
            if let name = app.localizedName,
               Self.screenShareProcessNames.contains(name) {
                return true
            }
        }

        return false
    }

    /// Whether a bundle ID belongs to a video conferencing app (as opposed to
    /// a dedicated screen recorder). Conferencing apps run in the background
    /// all the time, so we need extra signals to confirm active sharing.
    private func isConferencingApp(_ bundleId: String) -> Bool {
        let conferencingIds: Set<String> = [
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.cisco.webexmeetingsapp",
        ]
        return conferencingIds.contains(bundleId)
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

    /// Check the system window list for screen recording indicator windows.
    /// macOS shows a colored dot in the menu bar during recording — this
    /// manifests as a specific system window we can detect.
    private func checkWindowList() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        for info in windowList {
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            let windowName = info[kCGWindowName as String] as? String ?? ""
            let layer = info[kCGWindowLayer as String] as? Int ?? 0

            // The macOS screen recording indicator appears as a system-level
            // status item window. Also check for known sharing agent names.
            if ownerName == "ScreenSharingAgent" || ownerName == "screensharingd" {
                return true
            }

            // Check for "Screen Sharing" window from the built-in macOS
            // screen sharing service
            if ownerName == "Screen Sharing" || windowName.contains("Screen Sharing") {
                return true
            }

            // AirPlay receiver indicator
            if ownerName == "AirPlayUIAgent" && layer > 0 {
                return true
            }
        }

        return false
    }
}

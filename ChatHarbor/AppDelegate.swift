import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Shared reference to ServiceManager for checking notification settings
    static weak var serviceManager: ServiceManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when the app is in the foreground,
    /// respecting user's notification preferences
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            var options: UNNotificationPresentationOptions = []

            if let settings = AppDelegate.serviceManager?.notificationSettings {
                if settings.showBanners { options.insert(.banner) }
                if settings.playSound { options.insert(.sound) }
                if settings.showDockBadge { options.insert(.badge) }
            } else {
                // Fallback if serviceManager not yet set
                options = [.banner, .sound, .badge]
            }

            completionHandler(options)
        }
    }

    /// Handle notification taps — navigate to the originating service
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let serviceId = userInfo["serviceId"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .navigateToService,
                    object: nil,
                    userInfo: ["serviceId": serviceId]
                )
            }
        }
        completionHandler()
    }

    // MARK: - Dock Badge & Bounce

    static func updateDockBadge(count: Int) {
        if let settings = serviceManager?.notificationSettings, !settings.showDockBadge {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// Bounce the dock icon to get the user's attention for new messages
    static func bounceDockIcon() {
        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToService = Notification.Name("navigateToService")
}

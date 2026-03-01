import Foundation
import UserNotifications
import WebKit

// MARK: - Notification Bridge
//
// Injects JavaScript into each WKWebView to intercept the browser
// Notification API and forward notifications to native macOS
// notifications via a message handler.

class NotificationBridge: NSObject, WKScriptMessageHandler {

    let serviceId: String
    let serviceName: String
    weak var serviceManager: ServiceManager?

    init(serviceId: String, serviceName: String, serviceManager: ServiceManager?) {
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.serviceManager = serviceManager
        super.init()
    }

    // MARK: - JavaScript Injection

    /// JavaScript that overrides the browser Notification API and posts
    /// messages back to Swift via webkit.messageHandlers.
    static var injectionScript: String {
        return """
        (function() {
            // Store original Notification constructor
            const OriginalNotification = window.Notification;

            // Override the Notification constructor
            window.Notification = function(title, options) {
                // Forward to Swift
                window.webkit.messageHandlers.notificationBridge.postMessage({
                    type: 'notification',
                    title: title,
                    body: options?.body || '',
                    icon: options?.icon || '',
                    tag: options?.tag || ''
                });

                // Still create the original notification object for API compatibility
                try {
                    return new OriginalNotification(title, options);
                } catch(e) {
                    return {};
                }
            };

            // Copy static properties so services think they have permission
            window.Notification.permission = 'granted';
            window.Notification.requestPermission = function(callback) {
                if (callback) callback('granted');
                return Promise.resolve('granted');
            };

            // Observe title changes for unread count detection
            const titleObserver = new MutationObserver(function(mutations) {
                const title = document.title;
                window.webkit.messageHandlers.notificationBridge.postMessage({
                    type: 'titleChange',
                    title: title
                });
            });

            const titleEl = document.querySelector('title');
            if (titleEl) {
                titleObserver.observe(titleEl, { subtree: true, characterData: true, childList: true });
            } else {
                titleObserver.observe(document.head, { subtree: true, characterData: true, childList: true });
            }

            // Send initial title
            window.webkit.messageHandlers.notificationBridge.postMessage({
                type: 'titleChange',
                title: document.title
            });
        })();
        """
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        Task { @MainActor [self] in
            switch type {
            case "notification":
                handleWebNotification(body)
            case "titleChange":
                handleTitleChange(body)
            default:
                break
            }
        }
    }

    // MARK: - Notification Handling

    private func handleWebNotification(_ body: [String: Any]) {
        let title = body["title"] as? String ?? serviceName
        let messageBody = body["body"] as? String ?? ""

        let content = UNMutableNotificationContent()
        content.title = "\(serviceName): \(title)"
        content.body = messageBody
        content.sound = .default
        content.userInfo = ["serviceId": serviceId]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver notification: \(error.localizedDescription)")
            }
        }

        // Bounce the dock icon to alert the user
        AppDelegate.bounceDockIcon()
    }

    // MARK: - Unread Count from Title

    /// Many chat apps put unread counts in the page title, e.g. "(3) Slack"
    private func handleTitleChange(_ body: [String: Any]) {
        guard let title = body["title"] as? String else { return }

        let pattern = /\((\d+)\)/
        if let match = title.firstMatch(of: pattern),
           let count = Int(match.1) {
            let previousCount = serviceManager?.services.first(where: { $0.id == serviceId })?.notificationCount ?? 0
            serviceManager?.updateNotificationCount(for: serviceId, count: count)

            // Bounce dock if the count increased (new message arrived)
            if count > previousCount {
                AppDelegate.bounceDockIcon()
            }
        } else {
            serviceManager?.updateNotificationCount(for: serviceId, count: 0)
        }
    }
}

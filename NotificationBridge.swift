import Foundation
import UserNotifications
import WebKit

// MARK: - Notification Bridge
//
// This class injects JavaScript into each WKWebView to intercept
// the browser Notification API and forward notifications to native
// macOS notifications via a message handler.

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

    /// Returns the JavaScript that overrides the browser Notification API
    /// and posts messages back to Swift via webkit.messageHandlers.
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
                return new OriginalNotification(title, options);
            };

            // Copy static properties
            window.Notification.permission = 'granted';
            window.Notification.requestPermission = function(callback) {
                if (callback) callback('granted');
                return Promise.resolve('granted');
            };

            // Also observe title changes for unread count detection
            const titleObserver = new MutationObserver(function(mutations) {
                const title = document.title;
                window.webkit.messageHandlers.notificationBridge.postMessage({
                    type: 'titleChange',
                    title: title
                });
            });

            titleObserver.observe(
                document.querySelector('title') || document.head,
                { subtree: true, characterData: true, childList: true }
            );

            // Send initial title
            window.webkit.messageHandlers.notificationBridge.postMessage({
                type: 'titleChange',
                title: document.title
            });
        })();
        """
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "notification":
            handleWebNotification(body)
        case "titleChange":
            handleTitleChange(body)
        default:
            break
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
    }

    // MARK: - Unread Count from Title

    /// Many chat apps put unread counts in the page title, e.g. "(3) Slack"
    /// This parses that pattern and updates the dock badge.
    private func handleTitleChange(_ body: [String: Any]) {
        guard let title = body["title"] as? String else { return }

        let pattern = /\((\d+)\)/
        if let match = title.firstMatch(of: pattern),
           let count = Int(match.1) {
            DispatchQueue.main.async {
                self.serviceManager?.updateNotificationCount(for: self.serviceId, count: count)
            }
        } else {
            DispatchQueue.main.async {
                self.serviceManager?.updateNotificationCount(for: self.serviceId, count: 0)
            }
        }
    }
}

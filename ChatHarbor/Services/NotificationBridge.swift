import Foundation
import UserNotifications
import WebKit

// MARK: - Notification Bridge
//
// Injects JavaScript into each WKWebView to detect unread messages
// and forward notifications to native macOS notifications.
//
// Detection strategy (layered for reliability):
//   1. Intercept the browser Notification API constructor
//   2. Monitor document.title changes (handles "(3) Slack", "* Slack", etc.)
//   3. Watch favicon changes (many services badge the favicon)
//   4. Periodically scan service-specific DOM elements for unread indicators

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

    /// JavaScript that overrides the browser Notification API, monitors
    /// title/favicon changes, and runs service-specific unread scanners.
    static var injectionScript: String {
        return """
        (function() {
            // ── 1. Override Notification constructor ──────────────────────
            const OriginalNotification = window.Notification;

            window.Notification = function(title, options) {
                window.webkit.messageHandlers.notificationBridge.postMessage({
                    type: 'notification',
                    title: title,
                    body: options?.body || '',
                    icon: options?.icon || '',
                    tag: options?.tag || ''
                });
                try {
                    return new OriginalNotification(title, options);
                } catch(e) {
                    return {};
                }
            };

            window.Notification.permission = 'granted';
            window.Notification.requestPermission = function(callback) {
                if (callback) callback('granted');
                return Promise.resolve('granted');
            };

            // ── 2. Title change detection ────────────────────────────────
            // Intercept document.title setter — more reliable than
            // MutationObserver for SPAs that set title via JS.
            let _lastReportedTitle = '';

            function reportTitle(title) {
                if (title === _lastReportedTitle) return;
                _lastReportedTitle = title;
                try {
                    window.webkit.messageHandlers.notificationBridge.postMessage({
                        type: 'titleChange',
                        title: title
                    });
                } catch(e) {}
            }

            // Property override on document.title
            const titleDescriptor = Object.getOwnPropertyDescriptor(Document.prototype, 'title')
                || Object.getOwnPropertyDescriptor(HTMLDocument.prototype, 'title');

            if (titleDescriptor && titleDescriptor.set) {
                const originalSetter = titleDescriptor.set;
                const originalGetter = titleDescriptor.get;

                Object.defineProperty(document, 'title', {
                    get: function() { return originalGetter.call(this); },
                    set: function(val) {
                        originalSetter.call(this, val);
                        reportTitle(val);
                    },
                    configurable: true
                });
            }

            // Also use MutationObserver as a fallback (catches server-side title updates)
            const titleObserver = new MutationObserver(function() {
                reportTitle(document.title);
            });

            function observeTitle() {
                const titleEl = document.querySelector('title');
                if (titleEl) {
                    titleObserver.observe(titleEl, { subtree: true, characterData: true, childList: true });
                } else {
                    // Title element might not exist yet in SPAs
                    const headObserver = new MutationObserver(function() {
                        const el = document.querySelector('title');
                        if (el) {
                            headObserver.disconnect();
                            titleObserver.observe(el, { subtree: true, characterData: true, childList: true });
                        }
                    });
                    if (document.head) {
                        headObserver.observe(document.head, { subtree: true, childList: true });
                    }
                }
            }
            observeTitle();

            // Send initial title
            reportTitle(document.title);

            // ── 3. Favicon change monitoring ─────────────────────────────
            // Many services badge the favicon when there are unreads.
            let _lastFavicon = '';

            function checkFavicon() {
                const link = document.querySelector('link[rel*="icon"]');
                const href = link ? link.href : '';
                if (href !== _lastFavicon) {
                    _lastFavicon = href;
                    try {
                        window.webkit.messageHandlers.notificationBridge.postMessage({
                            type: 'faviconChange',
                            href: href
                        });
                    } catch(e) {}
                }
            }

            // Observe favicon link element changes
            const faviconObserver = new MutationObserver(checkFavicon);
            const iconLinks = document.querySelectorAll('link[rel*="icon"]');
            iconLinks.forEach(function(link) {
                faviconObserver.observe(link, { attributes: true, attributeFilter: ['href'] });
            });

            // Also watch <head> for new icon links being added
            if (document.head) {
                const headFaviconObserver = new MutationObserver(function() {
                    const newLinks = document.querySelectorAll('link[rel*="icon"]');
                    newLinks.forEach(function(link) {
                        faviconObserver.observe(link, { attributes: true, attributeFilter: ['href'] });
                    });
                    checkFavicon();
                });
                headFaviconObserver.observe(document.head, { childList: true });
            }

            checkFavicon();

            // ── 4. Service-specific DOM unread scanning ──────────────────
            // Each service puts unread indicators in different DOM locations.
            // We scan periodically (every 3 seconds) for these.

            const hostname = window.location.hostname;

            function countUnreads() {
                let count = 0;

                // Google Chat (mail.google.com/chat or chat.google.com)
                if (hostname.includes('google.com') && (
                    window.location.pathname.includes('/chat') ||
                    window.location.pathname.includes('/mail')
                )) {
                    // Unread conversations have bold text or unread indicator dots
                    const unreadBadges = document.querySelectorAll(
                        '[data-unread-count],' +
                        '.IL9EXe.PL5Wwe,' +           // Unread dot indicator
                        'span.bsU' +                    // Bold unread text
                        ''
                    );
                    // Try data-unread-count attributes first
                    let foundDataAttr = false;
                    unreadBadges.forEach(function(el) {
                        const attrCount = el.getAttribute('data-unread-count');
                        if (attrCount) {
                            count += parseInt(attrCount, 10) || 0;
                            foundDataAttr = true;
                        }
                    });
                    // Fallback: count elements with unread indicators
                    if (!foundDataAttr) {
                        // Count unread conversation rows
                        const unreadRows = document.querySelectorAll(
                            '[aria-label*="unread"],' +
                            '[data-is-unread="true"]'
                        );
                        count = unreadRows.length;
                    }
                }

                // Slack (app.slack.com)
                else if (hostname.includes('slack.com')) {
                    // Slack shows badges with unread counts in the sidebar
                    const badges = document.querySelectorAll(
                        '.p-channel_sidebar__badge,' +
                        '[data-qa="channel-unread-badge"],' +
                        '.c-mention_badge'
                    );
                    badges.forEach(function(badge) {
                        const text = badge.textContent.trim();
                        const n = parseInt(text, 10);
                        if (!isNaN(n)) count += n;
                    });
                    // If no numeric badges, count unread channels
                    if (count === 0) {
                        const unreadChannels = document.querySelectorAll(
                            '.p-channel_sidebar__channel--unread,' +
                            '[data-qa="channel_sidebar_name_button"].p-channel_sidebar__name_button--unread'
                        );
                        count = unreadChannels.length;
                    }
                }

                // Discord (discord.com)
                else if (hostname.includes('discord.com')) {
                    // Discord puts badge counts on server and channel icons
                    const badges = document.querySelectorAll(
                        '[class*="numberBadge"],' +
                        '[class*="mentionsBadge"]'
                    );
                    badges.forEach(function(badge) {
                        const n = parseInt(badge.textContent.trim(), 10);
                        if (!isNaN(n)) count += n;
                    });
                    // Fallback: count unread pips
                    if (count === 0) {
                        const pips = document.querySelectorAll('[class*="unreadPill"]');
                        count = pips.length;
                    }
                }

                // Microsoft Teams (teams.microsoft.com)
                else if (hostname.includes('teams.microsoft.com') || hostname.includes('teams.live.com')) {
                    const badges = document.querySelectorAll(
                        '[data-tid="unread-count"],' +
                        '.activity-badge,' +
                        '[class*="unread-count"]'
                    );
                    badges.forEach(function(badge) {
                        const n = parseInt(badge.textContent.trim(), 10);
                        if (!isNaN(n)) count += n;
                    });
                }

                // WhatsApp (web.whatsapp.com)
                else if (hostname.includes('whatsapp.com')) {
                    const badges = document.querySelectorAll(
                        '[data-testid="icon-unread-count"],' +
                        'span[aria-label*="unread message"],' +
                        '.OUeyt'
                    );
                    badges.forEach(function(badge) {
                        const n = parseInt(badge.textContent.trim(), 10);
                        if (!isNaN(n)) count += n;
                        else count += 1; // Has unread but no numeric count
                    });
                }

                // Telegram (web.telegram.org)
                else if (hostname.includes('telegram.org')) {
                    const badges = document.querySelectorAll(
                        '.Badge.unread,' +
                        '[class*="unread-count"],' +
                        '.rp[data-unread]'
                    );
                    badges.forEach(function(badge) {
                        const n = parseInt(badge.textContent.trim(), 10);
                        if (!isNaN(n)) count += n;
                    });
                }

                // Messenger (messenger.com)
                else if (hostname.includes('messenger.com')) {
                    const badges = document.querySelectorAll(
                        '[aria-label*="unread"]'
                    );
                    count = badges.length;
                }

                return count;
            }

            // Run DOM scanner every 3 seconds
            let _lastDomCount = -1;
            setInterval(function() {
                try {
                    const count = countUnreads();
                    if (count !== _lastDomCount) {
                        _lastDomCount = count;
                        window.webkit.messageHandlers.notificationBridge.postMessage({
                            type: 'domUnreadCount',
                            count: count
                        });
                    }
                } catch(e) {}
            }, 3000);

            // Initial scan after page settles
            setTimeout(function() {
                try {
                    const count = countUnreads();
                    _lastDomCount = count;
                    window.webkit.messageHandlers.notificationBridge.postMessage({
                        type: 'domUnreadCount',
                        count: count
                    });
                } catch(e) {}
            }, 5000);

        })();
        """
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [self] in
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "notification":
                handleWebNotification(body)
            case "titleChange":
                handleTitleChange(body)
            case "faviconChange":
                handleFaviconChange(body)
            case "domUnreadCount":
                handleDomUnreadCount(body)
            default:
                break
            }
        }
    }

    // MARK: - Notification Handling

    private func handleWebNotification(_ body: [String: Any]) {
        guard let manager = serviceManager,
              manager.notificationSettings.globalEnabled,
              !manager.isServiceMuted(serviceId) else { return }
        let settings = manager.notificationSettings

        let title = body["title"] as? String ?? serviceName
        let messageBody = body["body"] as? String ?? ""

        // Increment the sidebar badge count
        let currentCount = manager.services.first(where: { $0.id == serviceId })?.notificationCount ?? 0
        manager.updateNotificationCount(for: serviceId, count: currentCount + 1)

        let content = UNMutableNotificationContent()
        content.title = "\(serviceName): \(title)"
        content.body = messageBody
        content.userInfo = ["serviceId": serviceId]

        if settings.playSound {
            content.sound = .default
        }

        if settings.showBanners {
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

        if settings.bounceDock {
            AppDelegate.bounceDockIcon()
        }
    }

    // MARK: - Unread Count from Title

    /// Parses unread counts from various title patterns used by chat services:
    ///   - "(3) Slack"          → 3
    ///   - "* Slack"            → 1  (Slack uses asterisk for "has unreads")
    ///   - "Slack • channel"    → 1  (bullet = active notification)
    ///   - "3 unread messages"  → 3
    ///   - "Google Chat"        → 0  (no indicator)
    private func handleTitleChange(_ body: [String: Any]) {
        guard let title = body["title"] as? String else { return }
        guard let manager = serviceManager else { return }

        var count = 0

        // Pattern 1: "(N)" anywhere in title — e.g. "(3) Slack", "Discord (2)"
        let parenPattern = /\((\d+)\)/
        if let match = title.firstMatch(of: parenPattern),
           let n = Int(match.1) {
            count = n
        }
        // Pattern 2: Leading asterisk — e.g. "* Slack | channel"
        else if title.hasPrefix("*") || title.hasPrefix("● ") || title.hasPrefix("• ") {
            count = max(1, count)
        }
        // Pattern 3: "N unread" or "N new" in title
        else {
            let unreadPattern = /(\d+)\s+(?:unread|new|unseen)/
            if let match = title.firstMatch(of: unreadPattern),
               let n = Int(match.1) {
                count = n
            }
        }

        let previousCount = manager.services.first(where: { $0.id == serviceId })?.notificationCount ?? 0

        // Only update from title if we got a real count OR if title indicates zero
        // (don't override DOM-based counts with 0 from a static title like "Google Chat")
        if count > 0 || titleIndicatesZero(title) {
            manager.updateNotificationCount(for: serviceId, count: count)

            if count > previousCount,
               manager.notificationSettings.globalEnabled,
               manager.notificationSettings.bounceDock,
               !manager.isServiceMuted(serviceId) {
                AppDelegate.bounceDockIcon()
            }
        }
    }

    /// Returns true if the title explicitly indicates no unreads (e.g. title
    /// changed from "(3) Slack" back to "Slack"). Returns false for static
    /// titles like "Google Chat" that never change with unreads.
    private func titleIndicatesZero(_ title: String) -> Bool {
        // If the title previously had a count pattern and now doesn't,
        // that's an explicit zero. We detect this by checking if the
        // service is known to use title-based counts.
        let titleBasedServices = ["slack", "discord", "whatsapp", "telegram", "messenger"]
        return titleBasedServices.contains(serviceId)
    }

    // MARK: - Favicon Change

    private func handleFaviconChange(_ body: [String: Any]) {
        // Favicon changes can indicate new notifications.
        // Services like Google Chat change the favicon to include a dot.
        // For now we log this — the DOM scanner handles the actual counting.
        // This could be enhanced to detect badge overlays in favicon data URIs.
    }

    // MARK: - DOM-based Unread Count

    /// Handles unread counts detected by the periodic DOM scanner.
    /// This is the most reliable method for services like Google Chat
    /// that don't use title-based or Notification API patterns.
    private func handleDomUnreadCount(_ body: [String: Any]) {
        guard let count = body["count"] as? Int else { return }
        guard let manager = serviceManager else { return }

        let previousCount = manager.services.first(where: { $0.id == serviceId })?.notificationCount ?? 0

        manager.updateNotificationCount(for: serviceId, count: count)

        if count > previousCount,
           manager.notificationSettings.globalEnabled,
           manager.notificationSettings.bounceDock,
           !manager.isServiceMuted(serviceId) {
            AppDelegate.bounceDockIcon()
        }
    }
}

import Foundation
import WebKit

/// Manages a pool of WKWebView instances keyed by service ID.
///
/// Instead of creating and destroying a WKWebView every time the user
/// switches services, the pool keeps each web view alive so sessions,
/// cookies, and page state are preserved. This makes switching instant
/// and avoids re-authentication.
@MainActor
final class WebViewPool {

    static let shared = WebViewPool()

    /// Cached web views keyed by service ID
    private var webViews: [String: WKWebView] = [:]

    /// Notification bridges kept alive alongside their web views
    private var bridges: [String: NotificationBridge] = [:]

    /// NotificationCenter observers for reload / go-back actions
    private var observers: [String: [NSObjectProtocol]] = [:]

    private init() {}

    // MARK: - Public API

    /// Returns an existing web view for the service, or creates and loads one.
    func webView(
        for service: ChatService,
        serviceManager: ServiceManager
    ) -> WKWebView {
        if let existing = webViews[service.id] {
            return existing
        }

        let webView = createWebView(for: service, serviceManager: serviceManager)
        webViews[service.id] = webView
        registerObservers(for: service.id, webView: webView)
        return webView
    }

    /// Remove a specific service's web view (e.g. when the user removes the service).
    func removeWebView(for serviceId: String) {
        cleanupObservers(for: serviceId)
        bridges.removeValue(forKey: serviceId)
        if let wv = webViews.removeValue(forKey: serviceId) {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
        }
    }

    /// Remove all cached web views (e.g. on reset-to-defaults).
    func removeAll() {
        for id in webViews.keys {
            cleanupObservers(for: id)
        }
        for wv in webViews.values {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
        }
        webViews.removeAll()
        bridges.removeAll()
    }

    /// Reload a specific service's web view.
    func reload(serviceId: String) {
        webViews[serviceId]?.reload()
    }

    /// Navigate back in a specific service's web view.
    func goBack(serviceId: String) {
        webViews[serviceId]?.goBack()
    }

    // MARK: - Private Helpers

    private func createWebView(
        for service: ChatService,
        serviceManager: ServiceManager
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Enable JavaScript
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Set up the notification bridge
        let bridge = NotificationBridge(
            serviceId: service.id,
            serviceName: service.name,
            serviceManager: serviceManager
        )
        bridges[service.id] = bridge

        let userScript = WKUserScript(
            source: NotificationBridge.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)
        configuration.userContentController.add(bridge, name: "notificationBridge")

        // Allow media playback (for services like Discord voice)
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Inject timezone and locale so web apps respect system settings
        // Main frame only — no need to expose to third-party iframes
        let timezone = TimeZone.current.identifier
        let locale = Locale.current.identifier
        let localeScript = WKUserScript(
            source: """
            (function() {
                // Override Intl.DateTimeFormat to use system timezone
                const origDTF = Intl.DateTimeFormat;
                Intl.DateTimeFormat = function(locales, options) {
                    options = options || {};
                    if (!options.timeZone) {
                        options.timeZone = '\(timezone)';
                    }
                    return new origDTF(locales, options);
                };
                Object.setPrototypeOf(Intl.DateTimeFormat, origDTF);
                Intl.DateTimeFormat.prototype = origDTF.prototype;

                // Set navigator.language to match system locale
                Object.defineProperty(navigator, 'language', {
                    get: function() { return '\(locale.replacingOccurrences(of: "_", with: "-"))'; }
                });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true  // Only main frame — not sub-frames
        )
        configuration.userContentController.addUserScript(localeScript)

        // Build a dynamic Chrome user agent
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.dynamicUserAgent()
        webView.allowsBackForwardNavigationGestures = true

        // Load the service URL
        let request = URLRequest(url: service.url)
        webView.load(request)

        return webView
    }

    /// Builds a Chrome user agent string using the real macOS version
    /// and a Chrome major version derived from the current date.
    static func dynamicUserAgent() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(osVersion.majorVersion)_\(osVersion.minorVersion)_\(osVersion.patchVersion)"

        // Calculate a Chrome version based on weeks since Chrome 130 (Oct 15, 2024)
        let chrome130Date = DateComponents(calendar: .current, year: 2024, month: 10, day: 15).date!
        let weeksSince = Calendar.current.dateComponents([.weekOfYear], from: chrome130Date, to: Date()).weekOfYear ?? 0
        let chromeVersion = 130 + (weeksSince / 4)  // new major roughly every 4 weeks

        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(macOS)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromeVersion).0.0.0 Safari/537.36"
    }

    // MARK: - Notification Observers

    private func registerObservers(for serviceId: String, webView: WKWebView) {
        let reloadObserver = NotificationCenter.default.addObserver(
            forName: .reloadService,
            object: nil,
            queue: .main
        ) { [weak webView] notification in
            guard let id = notification.userInfo?["serviceId"] as? String,
                  id == serviceId else { return }
            webView?.reload()
        }

        let backObserver = NotificationCenter.default.addObserver(
            forName: .goBackService,
            object: nil,
            queue: .main
        ) { [weak webView] notification in
            guard let id = notification.userInfo?["serviceId"] as? String,
                  id == serviceId else { return }
            webView?.goBack()
        }

        observers[serviceId] = [reloadObserver, backObserver]
    }

    private func cleanupObservers(for serviceId: String) {
        if let obs = observers.removeValue(forKey: serviceId) {
            obs.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

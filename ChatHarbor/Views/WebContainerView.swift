import SwiftUI
import WebKit

// MARK: - Web Container View

struct WebContainerView: View {
    let service: ChatService
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            ChatWebView(
                service: service,
                serviceManager: serviceManager,
                isLoading: $isLoading,
                loadError: $loadError
            )

            if isLoading {
                ProgressView("Loading \(service.name)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }

            if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Failed to load \(service.name)")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        loadError = nil
                        isLoading = true
                        NotificationCenter.default.post(
                            name: .reloadService,
                            object: nil,
                            userInfo: ["serviceId": service.id]
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    NotificationCenter.default.post(
                        name: .reloadService,
                        object: nil,
                        userInfo: ["serviceId": service.id]
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload \(service.name)")

                Button {
                    NotificationCenter.default.post(
                        name: .goBackService,
                        object: nil,
                        userInfo: ["serviceId": service.id]
                    )
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Go Back")
            }
        }
    }
}

// MARK: - Notification Names for WebView Control

extension Notification.Name {
    static let reloadService = Notification.Name("reloadService")
    static let goBackService = Notification.Name("goBackService")
}

// MARK: - WKWebView Wrapper

struct ChatWebView: NSViewRepresentable {
    let service: ChatService
    let serviceManager: ServiceManager
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    /// Builds a Chrome user agent string using the real macOS version
    /// and a Chrome major version derived from the current date.
    /// Chrome releases roughly every 4 weeks; version 130 shipped Oct 2024.
    /// This formula keeps the version current without hardcoding.
    static func dynamicUserAgent() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(osVersion.majorVersion)_\(osVersion.minorVersion)_\(osVersion.patchVersion)"

        // Calculate a Chrome version based on weeks since Chrome 130 (Oct 15, 2024)
        let chrome130Date = DateComponents(calendar: .current, year: 2024, month: 10, day: 15).date!
        let weeksSince = Calendar.current.dateComponents([.weekOfYear], from: chrome130Date, to: Date()).weekOfYear ?? 0
        let chromeVersion = 130 + (weeksSince / 4)  // new major roughly every 4 weeks

        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(macOS)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromeVersion).0.0.0 Safari/537.36"
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Enable JavaScript
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Set up the notification bridge
        let bridge = NotificationBridge(
            serviceId: service.id,
            serviceName: service.name,
            serviceManager: serviceManager
        )
        context.coordinator.notificationBridge = bridge

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
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(localeScript)

        // Build a dynamic Chrome user agent using the real macOS version
        // and a Chrome version derived from the current date so it stays current
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = ChatWebView.dynamicUserAgent()

        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Load the service URL
        let request = URLRequest(url: service.url)
        webView.load(request)

        // Store reference for reload/navigation
        context.coordinator.webView = webView
        context.coordinator.registerForNotifications()

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No dynamic updates needed; WebView manages its own state
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator (Navigation + UI Delegate)

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: ChatWebView
        weak var webView: WKWebView?
        var notificationBridge: NotificationBridge?
        private var observers: [NSObjectProtocol] = []

        init(_ parent: ChatWebView) {
            self.parent = parent
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func registerForNotifications() {
            let reloadObserver = NotificationCenter.default.addObserver(
                forName: .reloadService,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let serviceId = notification.userInfo?["serviceId"] as? String,
                      serviceId == self?.parent.service.id else { return }
                self?.webView?.reload()
            }

            let backObserver = NotificationCenter.default.addObserver(
                forName: .goBackService,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let serviceId = notification.userInfo?["serviceId"] as? String,
                      serviceId == self?.parent.service.id else { return }
                self?.webView?.goBack()
            }

            observers = [reloadObserver, backObserver]
        }

        // MARK: - WKNavigationDelegate

        nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = true
                parent.loadError = nil
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = false
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                parent.isLoading = false
                parent.loadError = error.localizedDescription
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                parent.isLoading = false
                parent.loadError = error.localizedDescription
            }
        }

        // MARK: - WKUIDelegate

        /// Handle new window requests (target="_blank" links) by loading in the same view
        nonisolated func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// Handle permission requests for camera/microphone (Discord, Teams calls)
        nonisolated func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}

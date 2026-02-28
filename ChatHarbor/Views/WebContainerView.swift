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

        // Set a desktop user agent so services don't serve mobile versions
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

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

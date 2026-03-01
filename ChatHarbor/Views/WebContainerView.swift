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
            PooledWebView(
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

// MARK: - Pooled WKWebView Wrapper
//
// Uses WebViewPool to reuse web views across service switches.
// The web view is created once per service and kept alive in the pool,
// so switching back is instant and sessions/cookies are preserved.

struct PooledWebView: NSViewRepresentable {
    let service: ChatService
    let serviceManager: ServiceManager
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WebViewPool.shared.webView(
            for: service,
            serviceManager: serviceManager
        )

        // Attach delegates for loading state tracking
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView

        // If the web view already has content loaded, clear loading state
        if !webView.isLoading {
            DispatchQueue.main.async {
                isLoading = false
            }
        }

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
        let parent: PooledWebView
        weak var webView: WKWebView?

        init(_ parent: PooledWebView) {
            self.parent = parent
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

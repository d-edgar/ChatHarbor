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
            .blur(radius: serviceManager.shouldShowPrivacyShield ? 30 : 0)
            .animation(.easeInOut(duration: 0.3), value: serviceManager.shouldShowPrivacyShield)

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

            // MARK: - Privacy Shield Overlay
            if serviceManager.shouldShowPrivacyShield {
                PrivacyShieldOverlay()
                    .transition(.opacity)
            }

            // MARK: - Privacy Shield Countdown Pill
            if serviceManager.isPrivacyShieldTemporarilyDismissed && serviceManager.isScreenBeingShared {
                PrivacyShieldCountdownPill()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: serviceManager.isPrivacyShieldTemporarilyDismissed)
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
            Task { @MainActor in
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                }
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

// MARK: - Privacy Shield Overlay

struct PrivacyShieldOverlay: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "eye.slash.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(serviceManager.currentTheme.accentColor(for: colorScheme))
                    .symbolRenderingMode(.hierarchical)

                Text("Privacy Shield Active")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Your chats are hidden while your screen\nis being shared or recorded.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !ScreenShareDetector.shared.detectedAppName.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: ScreenShareDetector.shared.isManuallyEngaged
                              ? "hand.raised.fill" : "app.badge")
                            .font(.system(size: 11))
                        Text("Triggered by **\(ScreenShareDetector.shared.detectedAppName)**")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.top, 4)
                }

                Text("You can turn this off in Settings → Security.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)

                if ScreenShareDetector.shared.isManuallyEngaged {
                    Button {
                        ScreenShareDetector.shared.toggleManualEngagement()
                    } label: {
                        Label("Disengage Shield", systemImage: "eye")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(serviceManager.currentTheme.accentColor(for: colorScheme))
                    .padding(.top, 12)

                    Text("Or press ⌘⇧P to toggle.")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .padding(.top, 2)
                } else {
                    Button {
                        serviceManager.dismissPrivacyShieldTemporarily()
                    } label: {
                        Label("Continue for 5 Minutes", systemImage: "clock.badge.checkmark")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(serviceManager.currentTheme.accentColor(for: colorScheme))
                    .padding(.top, 12)

                    Text("The shield will re-engage automatically.")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .padding(.top, 2)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Privacy Shield Countdown Pill

struct PrivacyShieldCountdownPill: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, (serviceManager.privacyShieldDismissedUntil ?? .now).timeIntervalSince(context.date))
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60

            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation {
                            serviceManager.reengagePrivacyShield()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 11, weight: .medium))

                            Text("Shield paused · \(minutes):\(String(format: "%02d", seconds))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))

                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(serviceManager.currentTheme.accentColor(for: colorScheme).opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Re-engage Privacy Shield")
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
    }
}

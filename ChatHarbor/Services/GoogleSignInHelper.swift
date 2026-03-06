import Foundation
@preconcurrency import WebKit
import AppKit

/// Opens Google sign-in in a clean popup window that Google won't block.
///
/// Google blocks OAuth in embedded WKWebViews by fingerprinting the JavaScript
/// environment (e.g. `window.webkit.messageHandlers`). This helper creates a
/// temporary browser window with a *clean* WKWebView — no injected scripts or
/// message handlers — that shares cookies with the main web views via the same
/// `WKProcessPool`. After the user signs in, the redirect URL is loaded back
/// in the original web view and the popup closes automatically.
@MainActor
final class GoogleSignInHelper: NSObject {

    static let shared = GoogleSignInHelper()

    private var signInWindow: NSWindow?
    private var signInWebView: WKWebView?
    /// The original web view that initiated the sign-in flow
    private weak var originatingWebView: WKWebView?
    private var onComplete: (() -> Void)?

    // MARK: - Google OAuth URL Detection

    /// Domains that are part of Google's sign-in / consent flow.
    private static let googleAuthDomains: Set<String> = [
        "accounts.google.com",
        "accounts.youtube.com",
        "myaccount.google.com",
        "consent.google.com",
        "consent.youtube.com",
    ]

    /// Returns `true` if the URL is part of Google's sign-in / OAuth flow.
    /// Marked `nonisolated` so it can be called from WKNavigationDelegate methods.
    nonisolated static func isGoogleSignInURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return googleAuthDomains.contains(host)
    }

    // MARK: - Open Sign-In Window

    /// Present a popup browser window for Google sign-in.
    /// - Parameters:
    ///   - url: The `accounts.google.com` URL to load.
    ///   - originatingWebView: The web view that triggered the sign-in redirect.
    ///   - completion: Called when sign-in finishes (window closes).
    func openSignIn(
        url: URL,
        originatingWebView: WKWebView,
        completion: @escaping () -> Void
    ) {
        // If a sign-in window is already open, just bring it forward
        if let existing = signInWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        self.originatingWebView = originatingWebView
        onComplete = completion

        // Create a clean configuration — same process pool (shared cookies),
        // but NO message handlers or injected scripts
        let config = WKWebViewConfiguration()
        config.processPool = WebViewPool.shared.processPool
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        // Use Safari's user agent — Google trusts Safari on macOS
        webView.customUserAgent = Self.safariUserAgent()
        webView.navigationDelegate = self
        signInWebView = webView

        // Create a floating utility window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in with Google"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        signInWindow = window

        // Load the Google sign-in page
        webView.load(URLRequest(url: url))
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Cleanup

    /// Close the popup and optionally load a redirect URL in the original web view.
    private func closeWindow(redirectURL: URL? = nil) {
        signInWindow?.close()
        signInWebView?.navigationDelegate = nil
        signInWebView = nil
        signInWindow = nil

        // Load the post-auth redirect in the original web view
        if let url = redirectURL, let webView = originatingWebView {
            webView.load(URLRequest(url: url))
        }

        originatingWebView = nil
        let callback = onComplete
        onComplete = nil
        callback?()
    }

    // MARK: - Safari User Agent

    /// Builds a Safari user agent that Google trusts.
    private static func safariUserAgent() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(osVersion.majorVersion)_\(osVersion.minorVersion)_\(osVersion.patchVersion)"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(macOS)) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
    }
}

// MARK: - WKNavigationDelegate

extension GoogleSignInHelper: WKNavigationDelegate {

    /// Intercept navigations in the popup. Allow Google auth pages to load
    /// normally. When the flow redirects away from Google (back to the
    /// service), cancel it here and load that URL in the original web view.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Stay on Google auth pages — let them load in the popup
        if Self.isGoogleSignInURL(url) {
            decisionHandler(.allow)
            return
        }

        // Navigation is leaving Google auth (redirect back to the service).
        // Don't let it load in the popup — send it to the original web view.
        decisionHandler(.cancel)
        closeWindow(redirectURL: url)
    }
}

// MARK: - NSWindowDelegate

extension GoogleSignInHelper: NSWindowDelegate {

    /// If the user manually closes the window, clean up.
    func windowWillClose(_ notification: Notification) {
        let callback = onComplete
        onComplete = nil
        signInWebView?.navigationDelegate = nil
        signInWebView = nil
        signInWindow = nil
        originatingWebView = nil
        callback?()
    }
}

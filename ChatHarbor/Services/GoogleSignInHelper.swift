import Foundation
import WebKit
import AppKit

/// Opens Google sign-in in a clean popup window that Google won't block.
///
/// Google blocks OAuth in embedded WKWebViews by fingerprinting the JavaScript
/// environment (e.g. `window.webkit.messageHandlers`). This helper creates a
/// temporary browser window with a *clean* WKWebView — no injected scripts or
/// message handlers — that shares cookies with the main web views via the same
/// `WKProcessPool`. After the user signs in, cookies propagate automatically
/// and the popup closes.
@MainActor
final class GoogleSignInHelper: NSObject {

    static let shared = GoogleSignInHelper()

    private var signInWindow: NSWindow?
    private var signInWebView: WKWebView?
    private var onComplete: (() -> Void)?

    // MARK: - Google OAuth URL Detection

    /// Domains that indicate a Google sign-in flow.
    private static let googleAuthDomains: Set<String> = [
        "accounts.google.com",
        "accounts.youtube.com",
    ]

    /// Returns `true` if the URL is a Google sign-in / OAuth page.
    static func isGoogleSignInURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return googleAuthDomains.contains(host)
    }

    // MARK: - Open Sign-In Window

    /// Present a popup browser window for Google sign-in.
    /// - Parameters:
    ///   - url: The `accounts.google.com` URL to load.
    ///   - completion: Called when sign-in finishes (window closes).
    func openSignIn(url: URL, completion: @escaping () -> Void) {
        // If a sign-in window is already open, just bring it forward
        if let existing = signInWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

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

    private func closeWindow() {
        signInWindow?.close()
        signInWebView?.navigationDelegate = nil
        signInWebView = nil
        signInWindow = nil
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

    /// Monitor navigation — when the user finishes sign-in and is redirected
    /// away from Google's auth domain, close the popup.
    nonisolated func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        Task { @MainActor in
            guard let currentURL = webView.url else { return }

            // If we've navigated away from Google's auth pages, sign-in is complete
            if !Self.isGoogleSignInURL(currentURL) &&
               currentURL.host?.lowercased() != "myaccount.google.com" &&
               currentURL.host?.lowercased() != "consent.google.com" {
                closeWindow()
            }
        }
    }

    /// Allow all navigations within the sign-in window
    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - NSWindowDelegate

extension GoogleSignInHelper: NSWindowDelegate {

    /// If the user manually closes the window, clean up.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            let callback = onComplete
            onComplete = nil
            signInWebView?.navigationDelegate = nil
            signInWebView = nil
            signInWindow = nil
            callback?()
        }
    }
}

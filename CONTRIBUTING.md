# Contributing to ChatHarbor

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repo and clone your fork
2. Open `ChatHarbor.xcodeproj` in Xcode 16+
3. Set your signing team under Signing & Capabilities
4. Build and run (Cmd+R)

## Making Changes

- Create a branch from `main` for your work
- Keep commits focused — one logical change per commit
- Test your changes on macOS 14+

## Pull Requests

- Open a PR against `main`
- Describe what you changed and why
- Include screenshots for UI changes
- Make sure the project builds without warnings

## Reporting Bugs

Open an issue with:

- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

You can also use the in-app bug report at [chatharbor.app/bug-report](https://chatharbor.app/bug-report).

## Adding a New Service

If you want to add a preconfigured service, edit `ChatService.swift` and add an entry to the `preconfigured` array. Include the service name, URL, and an SF Symbol icon name.

## Testing Checklist

Before submitting a PR, verify these still work:

- Service switching and session persistence (web views stay logged in)
- Notifications and dock badge counts
- Google sign-in flow (should open in a popup window, not the embedded view)
- Camera/microphone permissions for voice/video services
- Keyboard shortcuts (Cmd+1 through Cmd+9, Cmd+R to reload)

## Code Style

- Follow existing Swift conventions in the project
- Use SwiftUI for new views
- Keep files focused — one view or model per file
- Mark classes that touch UI or WebKit with `@MainActor`
- Keep WKWebView logic in the Services layer, not in Views

## Architecture Notes

Web views are pooled in `WebViewPool` so switching services is instant and sessions persist. All web views share a single `WKProcessPool` for cookie sharing. Google sign-in is intercepted by the navigation delegate and routed through `GoogleSignInHelper`, which opens a clean popup window that Google trusts.

## Release Process

Releases are automated via GitHub Actions. When a version tag is pushed (e.g. `v1.0.15`), the workflow builds a universal binary, code-signs it, creates a styled DMG, notarizes it with Apple, and publishes a GitHub Release. Contributors don't need to worry about this — just submit your PR and the maintainers handle the release.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

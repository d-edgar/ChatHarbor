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
- Test your changes on macOS 15+

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

## Code Style

- Follow existing Swift conventions in the project
- Use SwiftUI for new views
- Keep files focused — one view or model per file

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

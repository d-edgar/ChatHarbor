# Contributing to ChatHarbor

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repo and clone your fork
2. Open `ChatHarbor.xcodeproj` in Xcode 16+
3. Set your signing team under Signing & Capabilities
4. Make sure Ollama is running locally (`ollama serve`)
5. Build and run (Cmd+R)

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
- Ollama version (`ollama --version`)
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

## Testing Checklist

Before submitting a PR, verify these still work:

- Ollama connection and model listing
- Streaming chat responses (tokens appear incrementally)
- Conversation creation, persistence, and deletion
- Model pulling and deletion via the Model Manager
- Keyboard shortcuts (⌘N new chat, ⌘M model manager, ⌘. stop generating)
- Theme switching and appearance modes
- Sidebar collapse/expand and conversation search

## Code Style

- Follow existing Swift conventions in the project
- Use SwiftUI for new views
- Keep files focused — one view or model per file
- Mark classes that touch UI with `@MainActor`
- Use SwiftData for any persistent state

## Architecture Notes

ChatHarbor uses a simple architecture: `ChatManager` is the central `ObservableObject` that coordinates between the UI and `OllamaService`. Conversations and messages are SwiftData `@Model` types persisted automatically. The Ollama service communicates with the local Ollama REST API, streaming responses via `URLSession.bytes`.

## Release Process

Releases are automated via GitHub Actions. When a version tag is pushed (e.g. `v2.0.0`), the workflow builds a universal binary, code-signs it, creates a styled DMG, notarizes it with Apple, and publishes a GitHub Release. Contributors don't need to worry about this — just submit your PR and the maintainers handle the release.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

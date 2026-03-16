# ChatHarbor

[![GitHub release](https://img.shields.io/github/v/release/d-edgar/ChatHarbor)](https://github.com/d-edgar/ChatHarbor/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-brightgreen)](https://github.com/d-edgar/ChatHarbor/releases/latest)

One native macOS app for all your AI. Chat with Claude, GPT, local models, and Apple Intelligence — or pit them against each other side by side. Brainstorm with structured creative frameworks. Built with SwiftUI and SwiftData. No Electron, no browser tabs, no switching apps.

## Why ChatHarbor?

You can't use Claude next to GPT. Every provider locks you into their own UI. If you want to compare answers, you're copying prompts between browser tabs. ChatHarbor fixes that.

It's a native macOS app that connects to Ollama (local models), OpenAI, Anthropic, and Apple Intelligence through a single interface. Same conversation UI, same streaming, same keyboard shortcuts — regardless of which AI you're talking to.

## What Makes ChatHarbor Different

- **All your AI in one place**: Ollama, OpenAI, Anthropic, and Apple Intelligence — one app, one conversation list, one compare view. Add your API keys and go, or use on-device Apple Intelligence for free.
- **Structured brainstorming**: Run guided brainstorm sessions using Osborn, Six Thinking Hats, Reverse Brainstorm, Round Robin, or fully custom frameworks. Each session walks through phases with user checkpoints, idea tracking, and exportable reports.
- **Cross-provider compare**: Send the same prompt to 2–4 models simultaneously. Watch them respond side by side. Compare quality, speed, and cost at a glance.
- **Fork to any model**: Having a conversation with Claude and want to see what GPT thinks? Right-click any message, choose "Fork to Model…", and replay the entire conversation history to a different AI. Supports nested forks.
- **Token & cost transparency**: Every response shows token count, estimated cost, and generation time. Click for a full usage breakdown per message and per conversation.
- **Prompt template library**: 8 built-in personas plus custom templates. Start conversations with purpose across any provider.
- **Markdown export**: Export any conversation as a clean `.md` file with model attribution and performance stats.
- **Truly native**: Real SwiftUI, real SwiftData persistence, real macOS integration. Not a web view.

## Supported Providers

| Provider | Type | Models | Setup |
|----------|------|--------|-------|
| **Ollama** | Local | llama3, mistral, codellama, etc. | Install Ollama, run `ollama serve` |
| **OpenAI** | Cloud | GPT-4o, GPT-4, o1, o3-mini, etc. | Add API key in Settings |
| **Anthropic** | Cloud | Claude Opus/Sonnet/Haiku | Add API key in Settings |
| **Apple Intelligence** | On-device | macOS 26+ built-in models | No setup — just works |

## Features

- **Native macOS app** built with SwiftUI — not a web view, not Electron
- **Multi-provider**: Ollama, OpenAI, Anthropic, and Apple Intelligence in one unified interface
- **Multi-method brainstorming**: Osborn, Six Thinking Hats, Reverse Brainstorm, Round Robin, or custom frameworks with phased progression and exportable reports
- **Model comparison**: send one prompt to 2–4 models and compare responses side by side
- **Conversation forking**: replay any conversation through a different model with nested fork support
- **Streaming responses**: tokens appear in real-time from any provider
- **Token & cost tracking**: per-message and per-conversation usage stats with built-in pricing for cloud providers
- **Conversation management**: create, search, and organize chats with SwiftData persistence
- **Model manager**: pull, switch, and delete local Ollama models
- **Prompt library**: 8 built-in templates plus unlimited custom presets
- **Themes**: 10 built-in color themes (6 standard + 4 seasonal) with light and dark mode variants
- **Keychain security**: API keys stored securely in macOS Keychain (auto-migrated from UserDefaults)
- **Resizable sidebar**: drag to resize (200–400px) or collapse to compact mode
- **Keyboard shortcuts**: ⌘N new chat, ⌘M models, ⇧⌘K compare, ⇧⌘P prompts, ⇧⌘B brainstorm, ⌘. stop
- **Per-conversation parameters**: override temperature, max tokens, top-p, and penalties per conversation
- **Signed and notarized**: releases are code-signed and notarized by Apple

## Requirements

- macOS 14 Sonoma or later
- At least one of:
  - [Ollama](https://ollama.com) installed and running (`ollama serve`) for local models
  - An [OpenAI](https://platform.openai.com/api-keys) API key for GPT models
  - An [Anthropic](https://console.anthropic.com/settings/keys) API key for Claude models
  - macOS 26+ for Apple Intelligence (no API key needed)

## Installation

### Download

Grab the latest `.dmg` from the [Releases](https://github.com/d-edgar/ChatHarbor/releases/latest) page. Open it, drag ChatHarbor to Applications, done.

### Build from Source

Requires Xcode 16+.

```bash
git clone https://github.com/d-edgar/ChatHarbor.git
cd ChatHarbor
open ChatHarbor.xcodeproj
```

Select your signing team under **Signing & Capabilities**, then build and run (⌘R).

## Usage

1. Make sure Ollama is running: `ollama serve`
2. Launch ChatHarbor
3. Pull a model if you haven't already (⌘M opens the Model Manager)
4. Click **New Chat** or press ⌘N
5. Start chatting

## Architecture

```
ChatHarbor/
  ChatHarborApp.swift          # App entry point, SwiftData container, scene config
  AppDelegate.swift            # Minimal app delegate
  ContentView.swift            # Main layout (sidebar + chat detail)
  Models/
    ChatModels.swift           # SwiftData models: Conversation, Message, CompareSlot, PromptTemplate
    BrainstormModels.swift     # BrainstormSession, BrainstormEntry, BrainstormMethod
    AppTheme.swift             # Theme definitions (10 themes)
  Services/
    LLMProvider.swift          # Unified provider protocol all backends conform to
    ProviderManager.swift      # Coordinates Ollama, OpenAI, Anthropic, Apple Intelligence
    ChatManager.swift          # Central state: chat, compare, fork, export, templates
    KeychainHelper.swift       # Secure API key storage with UserDefaults migration
    OllamaService.swift        # Ollama REST API client (streaming chat, pull, delete)
    OpenAIProvider.swift       # OpenAI /v1/chat/completions (streaming)
    AnthropicProvider.swift    # Anthropic /v1/messages (streaming)
    AppleIntelligenceProvider.swift  # On-device Apple Intelligence (macOS 26+)
  Views/
    SidebarView.swift          # Conversation list, model picker, search
    ChatView.swift             # Message bubbles, context menus (fork/export), input area
    CompareView.swift          # Multi-model side-by-side comparison
    BrainstormView.swift       # Structured brainstorming sessions
    PromptLibraryView.swift    # Template browser and editor
    ModelManagerView.swift     # Pull, select, and delete local models
    SettingsView.swift         # General, appearance, connection settings
    KeyboardShortcuts.swift    # Menu commands and keyboard shortcuts
```

## How It Works

ChatHarbor uses a unified `LLMProvider` protocol that all four providers conform to. Each provider handles its own API format (Ollama's `/api/chat`, OpenAI's `/v1/chat/completions`, Anthropic's `/v1/messages`, Apple Intelligence's on-device framework) but they all stream through the same interface. This means the compare view, conversation forking, brainstorming, and export work identically across providers. Conversations are persisted locally using SwiftData. API keys are stored securely in the macOS Keychain.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Ollama](https://ollama.com) for making local LLM inference simple
- [OpenAI](https://openai.com) and [Anthropic](https://anthropic.com) for cloud AI
- Apple for on-device intelligence
- Built with Swift, SwiftUI, and SwiftData

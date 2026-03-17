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
- **Structured brainstorming**: Run multi-phase brainstorm sessions with AI participants playing distinct roles — then ask follow-up questions in a dedicated Q&A mode. Supports five built-in methods plus fully custom frameworks. See [Brainstorm Mode](#brainstorm-mode) below.
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

## Brainstorm Mode

Brainstorm mode turns ChatHarbor into a structured creative thinking tool. Instead of a back-and-forth chat, you set up a session with a topic, choose a brainstorming method, assign AI participants to specific roles, and let them collaborate through a series of guided phases. Each participant contributes from their assigned perspective, and you can intervene at checkpoints to steer the conversation.

### How It Works

1. **Pick a method.** Choose from five built-in frameworks or create your own. Each method defines a set of phases the session progresses through automatically.
2. **Assign participants.** Add one or more AI models and assign each a role (e.g., Facilitator, Devil's Advocate, Optimist). Roles shape the system prompt each model receives, so participants genuinely argue from different angles. You can mix providers — have Claude facilitate while GPT-4o plays devil's advocate and a local Ollama model contributes wild ideas.
3. **Run the session.** The session advances through phases (e.g., Ideation → Critique → Refinement → Synthesis). At each checkpoint, you review what the participants have generated and decide whether to continue, redirect, or inject your own ideas.
4. **Ask follow-up questions.** After the session completes, a Q&A mode lets you chat with any model about the brainstorm's results — the full session context is included so the model can reference specific ideas, critiques, and outcomes. If you've already started a Q&A conversation, clicking the prompt resumes right where you left off.
5. **Export.** Export the entire session as Markdown or PDF, complete with participant attributions, phase labels, and token/cost stats.

### Built-in Methods

| Method | Phases | Best For |
|--------|--------|----------|
| **Osborn's Brainstorming** | Ideation → Critique → Refinement → Synthesis | Classic divergent-then-convergent thinking |
| **Six Thinking Hats** | Facts → Emotions → Risks → Benefits → Creativity → Process | Structured parallel thinking from multiple perspectives |
| **Reverse Brainstorm** | Anti-ideation → Analysis → Inversion → Synthesis | Finding solutions by first brainstorming ways to cause the problem |
| **Round Robin** | Multiple sequential rounds → Synthesis | Ensuring every participant contributes equally |
| **Custom** | You define the phases | Whatever structure fits your problem |

### Session Features

Each brainstorm entry shows the participant's role, the model used, the phase and round number, and a clickable stats pill with token count, generation speed, duration, and estimated cost. Clicking the pill opens a detailed usage popover with per-million-token pricing and a link to your provider's billing dashboard. Session-level stats in the header aggregate totals across all entries.

Completed sessions display a prominent Q&A card at the bottom of the timeline. If you've already had a Q&A conversation, it shows the model and message count and lets you resume directly. You can also start a new Q&A with a different model at any time.

Sessions can be rerun with the same or different participants, and individual failed entries can be retried with an alternate model.

## Features

- **Native macOS app** built with SwiftUI — not a web view, not Electron
- **Multi-provider**: Ollama, OpenAI, Anthropic, and Apple Intelligence in one unified interface
- **Multi-method brainstorming**: Osborn, Six Thinking Hats, Reverse Brainstorm, Round Robin, or custom frameworks with phased progression, role-based AI participants, post-session Q&A, and exportable reports (Markdown + PDF)
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
    BrainstormManager.swift    # Brainstorm session orchestration, streaming, Q&A mode
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

# ChatHarbor

[![GitHub release](https://img.shields.io/github/v/release/d-edgar/ChatHarbor)](https://github.com/d-edgar/ChatHarbor/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-brightgreen)](https://github.com/d-edgar/ChatHarbor/releases/latest)

A native macOS app for comparing AI models and working through ideas. Chat with cloud or local models, shortlist ideas, review disagreements, and turn a brainstorm into a decision brief. Built with SwiftUI and SwiftData.

## Recent development

Version 2.3.1 adds separate LM Studio and Other Servers settings, official Get links, and knowledge base links throughout the app. See [the changelog](CHANGELOG.md) for details and [GitHub Releases](https://github.com/d-edgar/ChatHarbor/releases) for published downloads.

Read the [knowledge base](https://chatharbor.app/help/) for setup, local models, Ships, Harbors, usage, and data controls.

### Getting started

Getting Started is an interactive guide that leaves the app usable. It highlights Chat, Models, Ships, and Harbors, then walks through connecting a model, sending a first message, optional Ship and Harbor setup, and data controls. Opening Settings or the Ship builder keeps your place. Model setup waits until you select an available model; the chat step waits for a user message. Nothing is sent automatically. Use **Back**, **Skip this step**, or **Skip tour** at any time; **Help → Getting Started** resumes your saved step, including after restarting. Only **Finish tour** marks it complete and hides the sidebar shortcut. After completion, Help starts a fresh tour.

## Why ChatHarbor?

ChatHarbor puts conversations, model comparisons, and structured brainstorming in one Mac app. Bring your own API keys or connect to a local model server.

It's a native macOS app that connects to Ollama (local models), OpenAI, Anthropic, Google Gemini, and Apple Intelligence through a single interface. Same conversation UI, same streaming, same keyboard shortcuts — regardless of which AI you're talking to.

## What Makes ChatHarbor Different

- **All your AI in one place**: Ollama, OpenAI, Anthropic, Google Gemini, and Apple Intelligence — one app, one conversation list, one compare view. Add your API keys and go, or use local models. Apple Intelligence requires a source build with Xcode 26+; the release workflow uses Xcode 16.4 and does not include that provider.
- **Structured brainstorming**: Run multi-phase brainstorm sessions with AI participants playing distinct roles — then ask follow-up questions in a dedicated Q&A mode. Supports four built-in methods plus a custom role setup. See [Brainstorm Mode](#brainstorm-mode) below.
- **Cross-provider compare**: Send the same prompt to 2–4 models simultaneously. Watch them respond side by side. Compare quality, input/output usage, speed, and estimated USD cost. Cost estimates use the built-in pricing table; models without a matching rate show “Cost unavailable.”
- **Fork to any model**: Having a conversation with Claude and want to see what GPT thinks? Right-click any message, choose "Fork to Model…", and replay the entire conversation history to a different AI. Supports nested forks.
- **Token & cost transparency**: Inspect input/output usage and generation time across chat, Ships, comparisons, brainstorming, and follow-up Q&A. Missing counts remain unknown, estimated counts are labeled, and cache/reasoning counts are treated as subsets. Cost is shown only when a supported rate is available.
- **Ships & Harbor**: Build custom AI workspaces called Ships. Each Ship has its own model, personality, knowledge base (URLs, files, text), and conversation history. Like custom GPTs, but for every provider. See [Ships & Harbor](#ships--harbor) below.
- **Prompt template library**: 8 built-in personas plus custom templates. Start conversations with purpose across any provider.
- **Markdown export**: Export any conversation as a clean `.md` file with model attribution and performance stats.
- **Truly native**: Real SwiftUI, real SwiftData persistence, real macOS integration. Not a web view.

## Supported Providers

| Provider | Type | Models | Setup |
|----------|------|--------|-------|
| **Ollama** | Local | llama3, mistral, codellama, etc. | Install Ollama, run `ollama serve` |
| **OpenAI** | Cloud | GPT-4o, GPT-4, o1, o3-mini, etc. | Add API key in Settings |
| **Anthropic** | Cloud | Claude Opus/Sonnet/Haiku | Add API key in Settings |
| **Google Gemini** | Cloud | Gemini 2.5 Pro/Flash, 2.0 Flash | Add API key in Settings |
| **LM Studio** | Local | Models downloaded in LM Studio | Start its local server; use Settings → Models → LM Studio |
| **Other Servers** | Any | Any OpenAI-compatible server | Add URL in Settings → Models → Other Servers |
| **Apple Intelligence** | On-device | Foundation Models (source builds with Xcode 26+) | Compatible Apple Silicon Mac, macOS 26+, Apple Intelligence enabled |

### LM Studio and Other Servers

ChatHarbor can connect to any server that exposes an OpenAI-compatible `/v1/chat/completions` endpoint. This includes LM Studio, LocalAI, Open WebUI, vLLM, text-generation-webui, Jan, and many others. You can add multiple endpoints, each with its own name and optional API key. Models are auto-discovered from each server's `/v1/models` endpoint. Endpoints running on localhost are automatically tagged as local in the model picker. Credentials are stored in Keychain. Model selections identify the specific endpoint, even when servers offer the same model. Older selections with multiple matching endpoints must be selected again to avoid sending a request to the wrong server.

## Brainstorm Mode

Brainstorm mode turns ChatHarbor into a structured creative thinking tool. Instead of a back-and-forth chat, you set up a session with a topic, choose a brainstorming method, assign AI participants to specific roles, and let them collaborate through a series of guided phases. Each participant contributes from their assigned perspective, and you can intervene at checkpoints to steer the conversation.

### Separate harbors for different parts of life

Use the harbor menu in the sidebar to create or switch between Personal, Work, or any other area. Each harbor has its own chats, ships, and brainstorms. Existing content appears in Personal, and the app remembers your selected harbor.

Right-click an item and choose **Move to Harbor** to reorganize it. Chats move with their forks; ships move with their conversation history. You can rename a harbor from the sidebar menu. Model connections, API keys, and app settings remain shared—harbors organize content within the same local database, rather than providing separate accounts or security boundaries.

### Deleting local data

Deleting a chat asks for confirmation. You can explicitly skip chat confirmations for five minutes; restarting the app clears that choice. Ships and brainstorms always ask, as do saved templates, cargo, and custom endpoints. Deleting a chat keeps its other forks; deleting a Ship also deletes its conversations and cargo.

Use **Settings → General → Data & Storage → Delete all ChatHarbor data** for a full reset. Type `DELETE` and choose **Delete & Quit**. Reopen ChatHarbor to finish the reset before any data loads. This removes every harbor, conversation, brainstorm, Ship, app setting, saved template, app cache, and ChatHarbor Keychain credential. If cleanup fails, startup offers Retry or Quit instead of opening partially reset data.

This is app-data deletion, not secure SSD erasure. Exports, backups, original cargo files, provider-side copies, and Ollama/LM Studio models remain outside its scope.

### Brainstorm entirely on your Mac

No cloud API key is needed when every participant uses a downloaded local model through Ollama or LM Studio running on your Mac:

1. Choose a local engine:
   - **Ollama:** install and start [Ollama](https://ollama.com), then download local models in **Settings → Models & Providers**.
   - **LM Studio:** download a model in [LM Studio](https://lmstudio.ai), then start its local server in the Developer tab. In ChatHarbor’s **Settings → Models & Providers → LM Studio & Other Servers**, select **LM Studio** and **Add**. The default address is `http://localhost:1234/v1`; edit it to match your server. Supply a key only if you enabled server authentication.
2. Start a brainstorm and choose those models for every active role. Use different models for different perspectives, or assign the same model to several roles.
3. Choose a local model for follow-up Q&A as well.

Participants take turns, so they do not need to generate simultaneously. Downloads need internet access; once the models are installed, local brainstorming can run offline. Model size and switching speed depend on your Mac. Use models served on this Mac; cloud models, remote endpoints, and remote inference routing are not local processing. Manage LM Studio model downloads and updates in LM Studio, then use **Refresh** on its ChatHarbor connection to rediscover available models. Other OpenAI compatible servers can use **Other compatible server** with their base URL and credentials.


### How It Works

1. **Pick a method.** Choose from four built-in methods or configure your own participant roles with Custom. Each method defines a set of phases the session progresses through automatically.
2. **Assign participants.** Add one or more AI models and assign each a role (e.g., Facilitator, Devil's Advocate, Optimist). Roles shape the system prompt each model receives, so you can compare responses from different perspectives. You can mix providers — have Claude facilitate while GPT-4o plays devil's advocate and a local Ollama model contributes wild ideas.
3. **Run and shortlist.** Review contributions at each checkpoint and add direction. Use **Your shortlist** to write or paste the ideas you want evaluated, one per line. Leave it blank to evaluate all ideas. Round Robin participants see earlier contributions in the same round.
4. **Review disagreements.** Before the decision brief, each enabled participant except the Scribe identifies a consequential disagreement or unresolved assumption and proposes a small test. Review this pass before continuing. The shortlist and disagreements are included in the final brief, exports, and follow-up Q&A.
5. **Ask follow-up questions.** After the session completes, a Q&A mode lets you chat with any model about the brainstorm's results — condensed session context is included, while the full transcript remains available in the report. If you've already started a Q&A conversation, clicking the prompt resumes right where you left off.
6. **Decide and revisit.** New synthesis responses produce a decision brief covering options, evidence, assumptions, disagreements, a recommendation, and a concrete experiment. At synthesis or completion, record your decision and reasoning in the follow-up card and return later to record outcomes and lessons. Notes and shortlists save as you type. Save failures remain visible with a retry action. Saved notes are included in exports and follow-up Q&A. Existing synthesis responses remain unchanged.
7. **Export.** Export the entire session as Markdown or PDF, complete with participant attributions, phase labels, and token/cost stats.

### Built-in Methods

| Method | Phases | Best For |
|--------|--------|----------|
| **Osborn's Brainstorming** | Framing → Ideation → Evaluation → Disagreements → Decision Brief | Classic divergent-then-convergent thinking |
| **Six Thinking Hats** | Framing → Hat Perspectives → Disagreements → Decision Brief | Structured parallel thinking from multiple perspectives |
| **Reverse Brainstorm** | Framing → Anti-ideation → Evaluation → Disagreements → Decision Brief | Finding solutions by first brainstorming ways to cause the problem |
| **Round Robin** | Framing → Sequential Rounds → Disagreements → Decision Brief | Ensuring every participant contributes equally |
| **Custom** | Framing → Ideation → Evaluation → Disagreements → Decision Brief | Choose your own participant roles |

### Session Features

Each brainstorm entry shows the participant's role, the model used, the phase and round number, and a clickable stats pill with token count, generation speed, duration, and estimated cost. Clicking the pill opens a detailed usage popover with per-million-token pricing and a link to your provider's billing dashboard. Session-level stats include brainstorm entries and follow-up Q&A. Unknown usage is not silently treated as zero.

Completed sessions display a prominent Q&A card at the bottom of the timeline. If you've already had a Q&A conversation, it shows the model and message count and lets you resume directly. You can also start a new Q&A with a different model at any time.

Sessions can be rerun with the same or different participants, and individual failed entries can be retried with an alternate model.

## Ships & Harbor

Ships are custom AI workspaces that go beyond prompt templates. Each Ship is a fully configured AI persona with its own model, personality, knowledge base, and conversation history.

### Building a Ship

Choose a harbor, then use the **Ships** section in the sidebar and click **Build your first Ship** or **+**. The Ship Builder has five configuration tabs:

**Identity** — name, icon (30+ SF Symbols), accent color, and tagline. This is how the Ship appears in the sidebar and model picker.

**Model** — choose any model from any provider (cloud or local) and optionally expand **Advanced model settings** for parameter overrides (temperature, max tokens, top-p). Every conversation in this Ship uses these settings automatically.

**Instructions** — the system prompt that defines how the Ship behaves: its tone, expertise, boundaries, and communication style.

**Knowledge** — the knowledge base. Load context from three sources: direct text (paste anything), URLs (fetched and stripped of HTML automatically), and files (txt, md, json, csv, html imported via file picker). All cargo is injected into the system prompt as reference material. A token budget indicator shows how much context window the cargo consumes.

**Response Rules** — conversation rules: focus topics (what the Ship specializes in) and response format instructions (e.g., "always use bullet points", "respond in JSON", "keep answers under 200 words").

### Using Ships

Click a Ship in the sidebar to enter its workspace. Every conversation inherits the Ship's full configuration. You can run multiple conversations per Ship, switch between them, and start new ones. The Ship's header shows the active model, cargo count, and conversation switcher.

## Features

- **Native macOS app** built with SwiftUI — not a web view, not Electron
- **Multi-provider**: Ollama, OpenAI, Anthropic, Google Gemini, and Apple Intelligence in one unified interface
- **Multi-method brainstorming**: Osborn, Six Thinking Hats, Reverse Brainstorm, Round Robin, or custom frameworks with phased progression, role-based AI participants, post-session Q&A, and exportable reports (Markdown + PDF)
- **Model comparison**: send one prompt to 2–4 models and compare responses side by side
- **Conversation forking**: replay any conversation through a different model with nested fork support
- **Streaming responses**: tokens appear in real-time from any provider
- **Token & cost tracking**: per-message and per-conversation usage stats with built-in pricing for cloud providers
- **Conversation management**: create, search, and organize chats with SwiftData persistence
- **Model manager**: pull, switch, and delete local Ollama models
- **Ships & Harbor**: custom AI workspaces with their own model, personality, knowledge base (URLs, files, text), and conversation history
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
  - A [Google AI Studio](https://aistudio.google.com/apikey) API key for Gemini models
  - A source build with Xcode 26+ on a compatible Apple Silicon Mac running macOS 26+ for Apple Intelligence (enable it in System Settings and ChatHarbor Settings)

## Installation

### Download

Grab the latest `.dmg` from the [Releases](https://github.com/d-edgar/ChatHarbor/releases/latest) page. Open it, drag ChatHarbor to Applications, done.

### Build from Source

Local builds require Xcode 16+; Command Line Tools alone are not enough. GitHub Actions builds on GitHub's Macs using their installed Xcode, so you do not need Xcode locally to use that workflow or install a released `.dmg`.

```bash
git clone https://github.com/d-edgar/ChatHarbor.git
cd ChatHarbor
open ChatHarbor.xcodeproj
```

Select your signing team under **Signing & Capabilities**, then build and run (⌘R).

## Usage

1. Launch ChatHarbor and choose **Connect a model**.
2. Add a cloud provider API key, or connect Ollama / LM Studio with a downloaded local model.
3. Return to the welcome screen and choose **Start a chat**.
4. Type a question and send it. No Ship setup is required.
5. Later, create a Ship to reuse instructions and knowledge, or another harbor to organize your work.

## Architecture

```
ChatHarbor/
  ChatHarborApp.swift          # App entry point, SwiftData container, scene config
  AppDelegate.swift            # Minimal app delegate
  ContentView.swift            # Main layout (sidebar + chat detail)
  Models/
    ChatModels.swift           # SwiftData models: Conversation, Message, CompareSlot, PromptTemplate
    BrainstormModels.swift     # BrainstormSession, BrainstormEntry, BrainstormMethod
    ShipModels.swift           # Ship, ShipConversation, ShipMessage, CargoItem
    AppTheme.swift             # Theme definitions (10 themes)
  Services/
    LLMProvider.swift          # Unified provider protocol all backends conform to
    ProviderManager.swift      # Coordinates all providers (Ollama, OpenAI, Anthropic, Gemini, Custom)
    CustomEndpointProvider.swift # User-defined OpenAI-compatible endpoints
    ChatManager.swift          # Central state: chat, compare, fork, export, templates
    BrainstormManager.swift    # Brainstorm session orchestration, streaming, Q&A mode
    KeychainHelper.swift       # Secure API key storage with UserDefaults migration
    OllamaService.swift        # Ollama REST API client (streaming chat, pull, delete)
    OpenAIProvider.swift       # OpenAI /v1/chat/completions (streaming)
    AnthropicProvider.swift    # Anthropic /v1/messages (streaming)
    GeminiProvider.swift       # Google Gemini generativelanguage API (streaming)
    AppleIntelligenceProvider.swift  # On-device Apple Intelligence (macOS 26+)
  Views/
    SidebarView.swift          # Conversation list, model picker, search
    ChatView.swift             # Message bubbles, context menus (fork/export), input area
    CompareView.swift          # Multi-model side-by-side comparison
    BrainstormView.swift       # Structured brainstorming sessions
    ShipBuilderView.swift      # Ship creation and editing (5-tab builder)
    ShipChatView.swift         # Conversation interface within a Ship
    PromptLibraryView.swift    # Template browser and editor
    ModelManagerView.swift     # Pull, select, and delete local models
    SettingsView.swift         # General, appearance, connection settings
    KeyboardShortcuts.swift    # Menu commands and keyboard shortcuts
```

## How It Works

ChatHarbor uses a unified `LLMProvider` protocol that the providers conform to. Each provider handles its own API format (Ollama's `/api/chat`, OpenAI's `/v1/chat/completions`, Anthropic's `/v1/messages`, Google's Gemini `generativelanguage` API, Apple Intelligence's on-device framework) but they all stream through the same interface. This means the compare view, conversation forking, brainstorming, and export work identically across providers. Conversations are persisted locally using SwiftData. API keys are stored securely in the macOS Keychain.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Ollama](https://ollama.com) for making local LLM inference simple
- [OpenAI](https://openai.com) and [Anthropic](https://anthropic.com) for cloud AI
- Apple for on-device intelligence
- Built with Swift, SwiftUI, and SwiftData

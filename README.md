# ChatHarbor

A lightweight, native macOS app that wraps your chat services into a single window with native notifications and dock badges. Built with Swift and WebKit, not Electron.

## Why ChatHarbor?

Every multi-chat app out there (Franz, Rambox, Ferdi, Ferdium, Station, Wavebox) is built on Electron, which means each one is basically running a full Chrome browser. That eats RAM and battery.

ChatHarbor uses macOS native WebKit (`WKWebView`), sharing the system Safari engine. This means significantly lower memory usage, better battery life, and a UI that actually feels like it belongs on a Mac.

## Features

- **Native macOS app** built with SwiftUI and WebKit
- **Preconfigured services**: Google Chat, Slack, Microsoft Teams, Discord
- **Custom services**: Add any web based chat or tool via URL
- **Native notifications**: Web notifications are bridged to macOS Notification Center
- **Dock badge**: Unread counts aggregated across all services
- **Keyboard shortcuts**: Cmd+1 through Cmd+9 to switch services, Cmd+R to reload
- **Camera and microphone support**: Works with voice/video calls in Teams, Discord, etc.
- **Reorderable sidebar**: Drag services into your preferred order
- **Lightweight**: Fraction of the memory footprint of Electron alternatives

## Requirements

- macOS 15 Sequoia or later
- Xcode 16+ (to build from source)

## Installation

### Build from Source

1. Clone the repository:
   ```
   git clone https://github.com/d-edgar/ChatHarbor.git
   ```
2. Open the project in Xcode
3. Select your signing team under Signing & Capabilities
4. Build and run (Cmd+R)

### Download Release

Check the [Releases](https://github.com/d-edgar/ChatHarbor/releases) page for prebuilt .dmg files.

## Usage

1. Launch ChatHarbor
2. Click a service icon in the sidebar to load it
3. Sign in to your accounts (sessions persist between launches)
4. Grant notification permissions when prompted
5. Use **Cmd+1** through **Cmd+9** to quickly switch between services
6. Open **Settings** (Cmd+,) to enable/disable services or add custom ones

## Architecture

```
ChatHarbor/
  ChatHarborApp.swift          # App entry point and scene configuration
  AppDelegate.swift           # Notification permissions and dock badge
  Models/
    ChatService.swift         # Service model with preconfigured definitions
  Services/
    ServiceManager.swift      # State management and persistence
    NotificationBridge.swift  # JS injection to bridge web notifications to native
  Views/
    ContentView.swift         # Main NavigationSplitView layout
    SidebarView.swift         # Service icons with notification badges
    WebContainerView.swift    # WKWebView wrapper with navigation controls
    SettingsView.swift        # Service management and about screen
    KeyboardShortcuts.swift   # Cmd+N shortcuts and menu commands
```

## How Notifications Work

ChatHarbor injects a small JavaScript snippet into each web view that overrides the browser `Notification` API. When a chat service triggers a web notification, the bridge captures it and creates a native `UNNotification` instead. It also watches for page title changes (many services show unread counts like "(3) Slack" in the title) to update the dock badge.

## Contributing

Contributions welcome. Open an issue or PR.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Disclaimer

ChatHarbor is not affiliated with Google, Slack, Microsoft, or Discord. All product names and trademarks are the property of their respective owners.

import SwiftUI
import SwiftData

struct ChatHarborCommands: Commands {
    @ObservedObject var chatManager: ChatManager

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Chat") {
                // Post notification — the ContentView will handle it
                NotificationCenter.default.post(name: .newChat, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Models") {
            Button("Models & Providers…") {
                chatManager.settingsTab = "models"
                chatManager.showingModelManager = true
            }
            .keyboardShortcut("m", modifiers: .command)

            Divider()

            Button("Refresh All Providers") {
                Task { await chatManager.providers.connectAll() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            // Quick model switching — all providers
            ForEach(Array(chatManager.providers.allModels.prefix(12)), id: \.id) { model in
                Button {
                    chatManager.selectModel(model.id)
                } label: {
                    HStack {
                        Text(model.displayName)
                        if model.id == chatManager.selectedModelId {
                            Text("✓")
                        }
                    }
                }
            }
        }

        CommandMenu("Chat") {
            Button("Stop Generating") {
                chatManager.stopGenerating()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!chatManager.isGenerating)

            Divider()

            Button("Compare Models") {
                chatManager.showingCompareView = true
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Prompt Library") {
                chatManager.showingPromptLibrary = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newChat = Notification.Name("chatHarbor.newChat")
}

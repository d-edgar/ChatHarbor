import SwiftUI

struct GettingStartedGuide: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.openSettings) private var openSettings
    let hasChat: Bool
    let hasUserMessage: Bool
    let startChat: () -> Void

    private var step: GettingStartedStep { chatManager.gettingStartedStep }
    private var modelAvailable: Bool {
        chatManager.providers.allModels.contains { $0.id == chatManager.selectedModelId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Getting Started · \(step.index + 1) of \(GettingStartedStep.allCases.count)", systemImage: "questionmark.circle")
                    .font(.headline)
                Spacer()
                Button("Skip tour") { chatManager.showingGettingStarted = false }
                    .help("Keep your place and resume from Help → Getting Started")
            }
            Text(step.title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            Text(step.explanation).fixedSize(horizontal: false, vertical: true)
            if step == .connect { TourModelSelection() }
            HStack {
                Button("Back") { chatManager.gettingStartedStep = step.previous }
                    .disabled(step == .overview)
                if step == .connect {
                    Button("Open model settings") {
                        chatManager.settingsTab = "models"
                        openSettings()
                    }
                } else if step == .chat && !hasChat {
                    Button("Start a chat", action: startChat).disabled(!modelAvailable)
                } else if step == .data {
                    Button("Open General settings") {
                        chatManager.settingsTab = "general"
                        openSettings()
                    }
                }
                if step == .chat && !modelAvailable {
                    Button("Connect a model") { chatManager.gettingStartedStep = .connect }
                }
                Spacer()
                if step == .connect || step == .chat {
                    Button("Skip this step") { chatManager.gettingStartedStep = step.next }
                }
                Button(step == .data ? "Finish tour" : "Continue") {
                    if step == .data {
                        UserDefaults.standard.set(true, forKey: "hasCompletedGettingStarted")
                        chatManager.showingGettingStarted = false
                        chatManager.gettingStartedStep = .overview
                    } else {
                        chatManager.gettingStartedStep = step.next
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!step.canContinue(modelAvailable: modelAvailable, hasUserMessage: hasUserMessage))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }
}

struct TourModelSelection: View {
    @EnvironmentObject var chatManager: ChatManager

    var body: some View {
        if chatManager.providers.allModels.isEmpty {
            Label("Waiting for a model. Connection errors appear beside the provider in Settings.", systemImage: "clock")
                .font(.callout)
        } else {
            Picker("Available model", selection: $chatManager.selectedModelId) {
                if !chatManager.providers.allModels.contains(where: { $0.id == chatManager.selectedModelId }) {
                    Text("Choose a model").tag(chatManager.selectedModelId)
                }
                ForEach(chatManager.providers.allModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .frame(maxWidth: 420)
            if chatManager.providers.allModels.contains(where: { $0.id == chatManager.selectedModelId }) {
                Label("Model available. Ready to try a chat.", systemImage: "checkmark.circle")
                    .font(.callout)
            }
        }
    }
}

struct TourSettingsHint: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Getting Started is waiting in the main window.").font(.headline)
            if chatManager.gettingStartedStep == .connect { TourModelSelection() }
            HStack {
                Text("Close Settings when you're ready. Your place is saved.").font(.callout)
                Spacer()
                Button("Return to tour") { dismiss() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
}

extension View {
    func tourHighlight(_ label: String, active: Bool) -> some View {
        overlay {
            if active {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if active {
                Text(label).font(.caption.bold())
                    .padding(.horizontal, 5)
                    .background(.regularMaterial, in: Capsule())
                    .offset(y: -7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

import SwiftUI
import SwiftData

// MARK: - Brainstorm Setup View
//
// The initial configuration screen for a brainstorm session.
// User enters their topic, assigns models to roles, and configures
// the number of ideation rounds before launching.

struct BrainstormSetupView: View {
    let session: BrainstormSession
    @EnvironmentObject var brainstormManager: BrainstormManager
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var topic: String = ""
    @State private var maxRounds: Int = 3
    @State private var selectedMethod: BrainstormMethod = .osborn
    @State private var participants: [BrainstormParticipant] = []
    @FocusState private var topicFocused: Bool

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    private var allModels: [ProviderModel] {
        chatManager.providers.allModels
    }

    /// Models grouped by provider for the pickers
    private var groupedModels: [(provider: String, models: [ProviderModel])] {
        let grouped = Dictionary(grouping: allModels, by: { $0.providerLabel })
        return grouped
            .sorted { $0.key < $1.key }
            .map { (provider: $0.key, models: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                // MARK: - Hero
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 44))
                        .foregroundStyle(accent)

                    Text("New Brainstorm")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Multiple AI models collaborate on your problem using structured brainstorming methods.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 600)
                }

                // MARK: - Method Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("BRAINSTORMING METHOD")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(BrainstormMethod.allCases) { method in
                            MethodCard(
                                method: method,
                                isSelected: selectedMethod == method,
                                accent: accent
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedMethod = method
                                    rebuildParticipants(for: method)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 740)

                // MARK: - Topic Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT DO YOU WANT TO BRAINSTORM?")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $topic)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 150)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                        .focused($topicFocused)

                    Text("Be specific. Good: \"How might we reduce onboarding time from 2 weeks to 3 days?\" Bad: \"Onboarding ideas\"")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 740)

                // MARK: - Role Assignment
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("ASSIGN ROLES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(enabledCount) of \(participants.count) active")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(participants.indices, id: \.self) { index in
                        RoleAssignmentRow(
                            participant: $participants[index],
                            groupedModels: groupedModels,
                            accent: accent,
                            isRequired: selectedMethod.requiredRoles.contains(participants[index].role)
                        )
                    }
                }
                .frame(maxWidth: 740)

                // MARK: - Settings
                VStack(alignment: .leading, spacing: 8) {
                    Text("SETTINGS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Text("Ideation Rounds")
                            .font(.system(size: 13))

                        Picker("", selection: $maxRounds) {
                            ForEach(1...5, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)

                        Text("More rounds = more ideas, longer sessions")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 740)

                // MARK: - How It Works
                howItWorks

                // MARK: - Launch Button
                Button {
                    launchBrainstorm()
                } label: {
                    Label("Start Brainstorm", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)
                .disabled(!canLaunch)

                if !canLaunch {
                    Text(launchBlocker)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            setupDefaults()
            topicFocused = true
        }
    }

    // MARK: - How It Works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: selectedMethod.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                Text("HOW \(selectedMethod.displayName.uppercased()) WORKS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(selectedMethod.phases.enumerated()), id: \.offset) { index, phase in
                    phaseCard(
                        icon: phase.icon,
                        title: "\(index + 1). \(phase.badgeName)",
                        description: phaseDescription(for: phase)
                    )
                }
            }
        }
        .frame(maxWidth: 740)
    }

    private func phaseDescription(for phase: BrainstormPhase) -> String {
        switch (selectedMethod, phase) {
        case (_, .framing):
            return "The facilitator reframes your topic into a clear problem statement. You approve before proceeding."
        case (.osborn, .ideation):
            return "Models take turns generating ideas. No criticism allowed — quantity over quality. You guide between rounds."
        case (.sixHats, .ideation):
            return "Each \"hat\" contributes their perspective — facts, emotions, risks, benefits, creativity. Parallel thinking from all angles."
        case (.reverse, .ideation):
            return "The Saboteur brainstorms ways to make things worse. Creative destruction as a springboard for real solutions."
        case (.roundRobin, .ideation):
            return "Contributors take equal turns, each building on what came before. Democratic and structured."
        case (.osborn, .evaluation):
            return "Models critique and refine. The devil's advocate stress-tests. You pick what survives."
        case (.reverse, .evaluation):
            return "The Inverter flips each sabotage idea into a genuine solution. Destruction becomes construction."
        case (_, .evaluation):
            return "Ideas are critiqued, combined, and refined by evaluators. The strongest survive."
        case (_, .synthesis):
            return "Final summary with action items and recommendations. Export-ready."
        default:
            return phase.description
        }
    }

    private func phaseCard(icon: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(accent)
                .frame(height: 24)

            Text(title)
                .font(.system(size: 12, weight: .semibold))

            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Logic

    private var enabledCount: Int {
        participants.filter(\.isEnabled).count
    }

    private var canLaunch: Bool {
        let hasText = !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let requiredMet = selectedMethod.requiredRoles.allSatisfy { req in
            participants.contains { $0.role == req && $0.isEnabled }
        }
        let hasAtLeastTwo = enabledCount >= 2
        return hasText && requiredMet && hasAtLeastTwo
    }

    private var launchBlocker: String {
        if topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a brainstorm topic above"
        }
        let missingRequired = selectedMethod.requiredRoles.filter { req in
            !participants.contains { $0.role == req && $0.isEnabled }
        }
        if let first = missingRequired.first {
            return "\(first.displayName) is required for \(selectedMethod.displayName)"
        }
        if enabledCount < 2 {
            return "Enable at least 2 roles"
        }
        return ""
    }

    private func setupDefaults() {
        // Restore from session if already configured
        if !session.participants.isEmpty {
            participants = session.participants
            topic = session.topic
            maxRounds = session.maxRounds
            selectedMethod = session.method
            return
        }

        // Use saved defaults from Settings
        maxRounds = chatManager.brainstormDefaultRounds
        selectedMethod = BrainstormMethod(rawValue: chatManager.brainstormDefaultMethod) ?? .osborn

        rebuildParticipants(for: selectedMethod)
    }

    /// Rebuild the participant list for a given method, preserving any model assignments
    private func rebuildParticipants(for method: BrainstormMethod) {
        let models = allModels
        let savedModels = chatManager.brainstormDefaultModels
        let enabledRoles = chatManager.brainstormEnabledRoles

        // Keep existing model assignments when switching methods
        let existingAssignments = Dictionary(
            participants.map { ($0.role.rawValue, $0.qualifiedModelId) },
            uniquingKeysWith: { first, _ in first }
        )

        guard !models.isEmpty else {
            participants = method.defaultRoles.map { role in
                BrainstormParticipant(role: role, qualifiedModelId: "", isEnabled: false)
            }
            return
        }

        let defaultModel = models.first?.id ?? ""

        func resolveModel(for role: BrainstormRole) -> String {
            // 1) Preserve existing assignment from the current session
            if let existing = existingAssignments[role.rawValue], !existing.isEmpty,
               models.contains(where: { $0.id == existing }) {
                return existing
            }
            // 2) Use the model saved in Settings if available
            if let savedId = savedModels[role.rawValue], !savedId.isEmpty,
               models.contains(where: { $0.id == savedId }) {
                return savedId
            }
            // 3) Fall back to smart keyword matching
            let keywords: [String]
            switch role {
            case .facilitator:    keywords = ["opus", "gpt-4o", "claude-sonnet", "llama"]
            case .wildCard:       keywords = ["sonnet", "gpt-4o-mini", "creative", "llama"]
            case .pragmatist:     keywords = ["o3", "o1", "sonnet", "gpt-4o", "qwen"]
            case .devilsAdvocate: keywords = ["sonnet", "gpt-4o", "opus", "mistral"]
            case .scribe:         keywords = ["haiku", "gpt-4o-mini", "apple", "phi"]
            case .whitHat:        keywords = ["sonnet", "gpt-4o", "opus", "llama"]
            case .redHat:         keywords = ["sonnet", "gpt-4o-mini", "haiku", "llama"]
            case .blackHat:       keywords = ["opus", "o3", "gpt-4o", "sonnet"]
            case .yellowHat:      keywords = ["sonnet", "gpt-4o-mini", "haiku", "llama"]
            case .greenHat:       keywords = ["sonnet", "gpt-4o-mini", "creative", "llama"]
            case .saboteur:       keywords = ["sonnet", "gpt-4o", "opus", "llama"]
            case .inverter:       keywords = ["opus", "gpt-4o", "sonnet", "llama"]
            case .contributor:    keywords = ["sonnet", "gpt-4o-mini", "haiku", "llama"]
            }
            for keyword in keywords {
                if let match = models.first(where: { $0.modelId.lowercased().contains(keyword.lowercased()) }) {
                    return match.id
                }
            }
            return defaultModel
        }

        let isRequired = Set(method.requiredRoles.map(\.rawValue))
        participants = method.defaultRoles.map { role in
            let required = isRequired.contains(role.rawValue)
            return BrainstormParticipant(
                role: role,
                qualifiedModelId: resolveModel(for: role),
                isEnabled: required || enabledRoles.contains(role.rawValue)
            )
        }
    }

    private func launchBrainstorm() {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else { return }

        session.topic = trimmedTopic
        session.title = session.autoTitle
        session.method = selectedMethod
        session.participants = participants
        session.maxRounds = maxRounds
        session.updatedAt = Date()
        try? modelContext.save()

        brainstormManager.run(session: session, context: modelContext)
    }
}

// MARK: - Role Assignment Row

struct RoleAssignmentRow: View {
    @Binding var participant: BrainstormParticipant
    let groupedModels: [(provider: String, models: [ProviderModel])]
    let accent: Color
    var isRequired: Bool = false

    private var roleColor: Color {
        colorForRole(participant.role.color)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle (disabled for required roles)
            Toggle("", isOn: $participant.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isRequired)

            // Role icon
            Image(systemName: participant.role.icon)
                .font(.system(size: 16))
                .foregroundStyle(participant.isEnabled ? roleColor : .gray)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(participant.isEnabled ? roleColor.opacity(0.1) : Color.gray.opacity(0.06))
                )

            // Role name + description
            VStack(alignment: .leading, spacing: 3) {
                Text(participant.role.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(participant.isEnabled ? .primary : .secondary)

                Text(participant.role.shortDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Active phases badges
                HStack(spacing: 4) {
                    ForEach(participant.role.activePhases, id: \.self) { phase in
                        Text(phase.badgeName)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(roleColor.opacity(0.08), in: Capsule())
                            .foregroundStyle(roleColor)
                            .fixedSize()
                    }
                }
            }

            Spacer(minLength: 12)

            // Model picker
            Picker("", selection: $participant.qualifiedModelId) {
                if participant.qualifiedModelId.isEmpty {
                    Text("Select Model").tag("")
                }
                ForEach(groupedModels, id: \.provider) { group in
                    Section(group.provider) {
                        ForEach(group.models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                }
            }
            .frame(width: 200)
            .disabled(!participant.isEnabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(participant.isEnabled ? roleColor.opacity(0.03) : Color.gray.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(participant.isEnabled ? roleColor.opacity(0.12) : Color.gray.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Method Card

struct MethodCard: View {
    let method: BrainstormMethod
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: method.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? accent : .secondary)

                    Text(method.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(accent)
                    }
                }

                Text(method.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Phase flow preview
                HStack(spacing: 4) {
                    ForEach(method.phases, id: \.self) { phase in
                        Text(phase.badgeName)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accent.opacity(isSelected ? 0.1 : 0.05), in: Capsule())
                            .foregroundStyle(isSelected ? accent : .secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accent.opacity(0.05) : Color.gray.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? accent.opacity(0.3) : Color.gray.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Color Helper

/// Maps a BrainstormRole.color string to a SwiftUI Color
func colorForRole(_ colorName: String) -> Color {
    switch colorName {
    case "blue": return .blue
    case "purple": return .purple
    case "green": return .green
    case "orange": return .orange
    case "teal": return .teal
    case "red": return .red
    case "yellow": return .yellow
    case "black": return .primary
    case "indigo": return .indigo
    case "gray": return .gray
    default: return .gray
    }
}

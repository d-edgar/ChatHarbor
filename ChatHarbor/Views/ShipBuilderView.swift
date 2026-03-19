import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Ship Builder View
//
// The creation and editing interface for Ships. Organized into sections:
// Identity (name, icon, color), Engine (model, parameters), Personality
// (system prompt, tagline), Cargo (knowledge), and Heading (rules).

struct ShipBuilderView: View {
    @Bindable var ship: Ship
    let isNew: Bool
    var onSave: () -> Void
    var onCancel: () -> Void

    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSection: BuilderSection = .identity
    @State private var newCargoURL: String = ""
    @State private var isFetchingURL: Bool = false
    @State private var cargoError: String?

    private var accent: Color {
        Color(hex: ship.colorHex) ?? .blue
    }

    enum BuilderSection: String, CaseIterable {
        case identity = "Identity"
        case engine = "Engine"
        case personality = "Personality"
        case cargo = "Cargo"
        case heading = "Heading"

        var icon: String {
            switch self {
            case .identity: return "tag"
            case .engine: return "engine.combustion"
            case .personality: return "person.text.rectangle"
            case .cargo: return "shippingbox"
            case .heading: return "safari"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: ship.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
                Text(isNew ? "Build a New Ship" : "Edit \(ship.name)")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()

                // Context budget indicator
                let tokens = ship.estimatedContextTokens
                if tokens > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.medium")
                            .font(.system(size: 10))
                        Text("~\(formatTokens(tokens)) context tokens")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(tokens > 100_000 ? .orange : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.3), in: Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Section tabs
            HStack(spacing: 2) {
                ForEach(BuilderSection.allCases, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: section.icon)
                                .font(.system(size: 10))
                            Text(section.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selectedSection == section ? accent : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedSection == section
                                ? accent.opacity(colorScheme == .dark ? 0.15 : 0.1)
                                : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Section content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSection {
                    case .identity:
                        identitySection
                    case .engine:
                        engineSection
                    case .personality:
                        personalitySection
                    case .cargo:
                        cargoSection
                    case .heading:
                        headingSection
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer actions
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                if !isNew {
                    Text("Last updated \(ship.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isNew ? "Launch Ship" : "Save Changes") {
                    ship.updatedAt = Date()
                    onSave()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(ship.name.isEmpty || ship.modelId.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "IDENTITY", subtitle: "Name and appearance of your Ship")

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Ship Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g., Code Reviewer, Legal Analyst, IT Support Bot", text: $ship.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            // Tagline
            VStack(alignment: .leading, spacing: 4) {
                Text("Tagline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Short description shown in the Harbor", text: $ship.tagline)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 10), spacing: 6) {
                    ForEach(ShipIconOptions.icons, id: \.symbol) { option in
                        Button {
                            ship.icon = option.symbol
                        } label: {
                            Image(systemName: option.symbol)
                                .font(.system(size: 14))
                                .frame(width: 32, height: 32)
                                .background(
                                    ship.icon == option.symbol
                                        ? accent.opacity(0.15)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            ship.icon == option.symbol ? accent : .clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.label)
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(ShipIconOptions.colors, id: \.hex) { option in
                        Button {
                            ship.colorHex = option.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: option.hex) ?? .blue)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(.white, lineWidth: ship.colorHex == option.hex ? 2 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(
                                            ship.colorHex == option.hex ? (Color(hex: option.hex) ?? .blue) : .clear,
                                            lineWidth: 3
                                        )
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(option.label)
                    }
                }
            }

            // Preview
            HStack(spacing: 10) {
                Image(systemName: ship.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ship.name.isEmpty ? "Untitled Ship" : ship.name)
                        .font(.system(size: 13, weight: .semibold))
                    if !ship.tagline.isEmpty {
                        Text(ship.tagline)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Engine Section

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "ENGINE", subtitle: "Choose the model and tune its parameters")

            // Model picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Base Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("Model", selection: $ship.modelId) {
                    Text("Select a model...").tag("")
                    ForEach(chatManager.providers.allModels) { model in
                        HStack {
                            Image(systemName: model.isLocal ? "desktopcomputer" : "cloud")
                            Text(model.displayName)
                            Text("(\(model.providerLabel))")
                                .foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                }
                .labelsHidden()
            }

            // Parameters
            VStack(alignment: .leading, spacing: 12) {
                Text("Parameter Overrides")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Leave blank to use the model's defaults")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                parameterRow("Temperature", value: $ship.temperature, range: 0...2, step: 0.1)
                parameterRow("Max Tokens", intValue: $ship.maxTokens, range: 1...128000)
                parameterRow("Top P", value: $ship.topP, range: 0...1, step: 0.05)
            }
        }
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "PERSONALITY", subtitle: "Define how this Ship behaves and communicates")

            VStack(alignment: .leading, spacing: 4) {
                Text("System Prompt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $ship.systemPrompt)
                    .font(.system(size: 12))
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                Text("\(ship.systemPrompt.count) characters · ~\(ship.systemPrompt.count / 4) tokens")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Cargo Section

    private var cargoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "CARGO", subtitle: "Knowledge base — text, URLs, and files that give this Ship context")

            // Direct text knowledge
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Knowledge Text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !ship.knowledgeText.isEmpty {
                        Text("~\(ship.knowledgeText.count / 4) tokens")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                TextEditor(text: $ship.knowledgeText)
                    .font(.system(size: 11))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }

            Divider()

            // Add URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Add URL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("https://example.com/docs", text: $newCargoURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    if isFetchingURL {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Button("Fetch") {
                            fetchURL()
                        }
                        .controlSize(.small)
                        .disabled(newCargoURL.isEmpty)
                    }
                }

                if let error = cargoError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            // Add files
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Files")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button {
                    importFiles()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.plus")
                        Text("Import Documents")
                    }
                    .font(.system(size: 11))
                }
                .controlSize(.small)

                Text("Supports .txt, .md, .json, .csv, .html files")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Existing cargo items
            if !ship.cargoItems.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("LOADED CARGO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        let totalTokens = ship.cargoItems.reduce(0) { $0 + $1.estimatedTokens }
                        Text("~\(formatTokens(totalTokens)) tokens total")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(ship.cargoItems) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.sourceType == .url ? "link" : item.sourceType == .file ? "doc" : "text.alignleft")
                                .font(.system(size: 10))
                                .foregroundStyle(accent)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text("~\(formatTokens(item.estimatedTokens)) tokens")
                                    if let date = item.fetchedAt {
                                        Text("· fetched \(date.formatted(.relative(presentation: .named)))")
                                    }
                                }
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            // Refresh (URLs only)
                            if item.sourceType == .url {
                                Button {
                                    refreshCargoItem(item)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help("Re-fetch URL content")
                            }

                            // Remove
                            Button {
                                removeCargoItem(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from cargo")
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - Heading Section

    private var headingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "HEADING", subtitle: "Guide what this Ship focuses on and how it responds")

            VStack(alignment: .leading, spacing: 4) {
                Text("Focus Topics")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("What domains or topics should this Ship specialize in?")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextEditor(text: $ship.focusTopics)
                    .font(.system(size: 12))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Response Format")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("How should responses be formatted? (e.g., always use bullet points, respond in JSON, keep answers under 200 words)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextEditor(text: $ship.responseFormat)
                    .font(.system(size: 12))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Helpers

    private func parameterRow(_ label: String, value: Binding<Double?>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 100, alignment: .trailing)
            TextField("Default", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 80)
            if let val = value.wrappedValue {
                Slider(value: Binding(
                    get: { val },
                    set: { value.wrappedValue = $0 }
                ), in: range, step: step)
                .frame(width: 120)
            }
        }
    }

    private func parameterRow(_ label: String, intValue: Binding<Int?>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 100, alignment: .trailing)
            TextField("Default", value: intValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 80)
        }
    }

    private func fetchURL() {
        guard let url = URL(string: newCargoURL), url.scheme != nil else {
            cargoError = "Invalid URL"
            return
        }
        isFetchingURL = true
        cargoError = nil

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: request)
                let text = String(data: data, encoding: .utf8) ?? ""

                // Strip HTML tags for a rough text extraction
                let cleanText = text
                    .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let item = CargoItem(
                    title: url.host ?? newCargoURL,
                    source: newCargoURL,
                    sourceType: .url,
                    content: String(cleanText.prefix(100_000)), // Cap at ~25K tokens
                    fetchedAt: Date(),
                    sizeBytes: data.count
                )

                var items = ship.cargoItems
                items.append(item)
                ship.cargoItems = items

                newCargoURL = ""
            } catch {
                cargoError = "Failed to fetch: \(error.localizedDescription)"
            }
            isFetchingURL = false
        }
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .plainText, .json, .html,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "csv") ?? .plainText,
        ]

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                let item = CargoItem(
                    title: url.lastPathComponent,
                    source: url.path,
                    sourceType: .file,
                    content: String(text.prefix(100_000)),
                    fetchedAt: Date(),
                    sizeBytes: data.count
                )

                var items = ship.cargoItems
                items.append(item)
                ship.cargoItems = items
            }
        }
    }

    private func removeCargoItem(_ item: CargoItem) {
        var items = ship.cargoItems
        items.removeAll { $0.id == item.id }
        ship.cargoItems = items
    }

    private func refreshCargoItem(_ item: CargoItem) {
        guard item.sourceType == .url, let url = URL(string: item.source) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let text = String(data: data, encoding: .utf8) ?? ""
                let cleanText = text
                    .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                var items = ship.cargoItems
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].content = String(cleanText.prefix(100_000))
                    items[index].fetchedAt = Date()
                    items[index].sizeBytes = data.count
                }
                ship.cargoItems = items
            } catch {
                cargoError = "Failed to refresh \(item.title): \(error.localizedDescription)"
            }
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Color from Hex

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}

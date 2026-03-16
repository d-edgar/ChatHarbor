import SwiftUI
import SwiftData

// MARK: - Prompt Library View
//
// Browse, create, and manage prompt templates (system prompts).
// Use a template to start a new conversation with a pre-configured persona.

struct PromptLibraryView: View {
    @EnvironmentObject var chatManager: ChatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var showingNewTemplate: Bool = false
    @State private var editingTemplate: PromptTemplate?

    private var accent: Color {
        chatManager.currentTheme.accentColor(for: colorScheme)
    }

    private var filteredTemplates: [PromptTemplate] {
        let all = chatManager.allTemplates
        if searchText.isEmpty { return all }
        let query = searchText.lowercased()
        return all.filter {
            $0.name.lowercased().contains(query) ||
            $0.systemPrompt.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 16))
                    .foregroundStyle(accent)
                Text("Prompt Library")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()

                Button {
                    showingNewTemplate = true
                } label: {
                    Label("New Template", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // MARK: - Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search templates…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // MARK: - Template Grid
            ScrollView {
                if filteredTemplates.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No templates match your search")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ], spacing: 12) {
                        ForEach(filteredTemplates) { template in
                            TemplateCard(template: template, accent: accent) {
                                startConversation(with: template)
                            } onEdit: {
                                editingTemplate = template
                            } onDelete: {
                                chatManager.deleteTemplate(template)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showingNewTemplate) {
            TemplateEditorSheet(accent: accent) { newTemplate in
                chatManager.addTemplate(newTemplate)
            }
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(accent: accent, existing: template) { updated in
                chatManager.updateTemplate(updated)
            }
        }
    }

    private func startConversation(with template: PromptTemplate) {
        let conversation = chatManager.createConversation(
            in: modelContext,
            systemPrompt: template.systemPrompt
        )
        conversation.title = template.name == "Default" ? "New Conversation" : "\(template.name) Chat"
        try? modelContext.save()
        chatManager.showingPromptLibrary = false
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: PromptTemplate
    let accent: Color
    let onUse: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: template.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                Text(template.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                if template.isBuiltIn {
                    Text("BUILT-IN")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
            }

            if template.systemPrompt.isEmpty {
                Text("No system prompt — default behavior")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(template.systemPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    onUse()
                } label: {
                    Label("Start Chat", systemImage: "plus.bubble")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.mini)

                Spacer()

                if !template.isBuiltIn {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Edit template")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete template")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? accent.opacity(0.04) : Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovering ? accent.opacity(0.2) : Color.gray.opacity(0.15), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Template Editor Sheet

struct TemplateEditorSheet: View {
    let accent: Color
    var existing: PromptTemplate?
    let onSave: (PromptTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var systemPrompt: String = ""
    @State private var icon: String = "text.bubble"

    private let iconOptions = [
        "text.bubble", "brain.head.profile", "hammer", "leaf",
        "paintbrush", "music.note", "chart.bar", "globe",
        "lightbulb", "flag", "heart", "star",
        "bolt", "shield", "book", "graduationcap"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existing == nil ? "New Template" : "Edit Template")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            Form {
                Section("Details") {
                    TextField("Template name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    // Icon picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8), spacing: 6) {
                            ForEach(iconOptions, id: \.self) { iconName in
                                Button {
                                    icon = iconName
                                } label: {
                                    Image(systemName: iconName)
                                        .font(.system(size: 13))
                                        .frame(width: 28, height: 28)
                                        .background(
                                            icon == iconName ? accent.opacity(0.15) : Color.gray.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(icon == iconName ? accent : .clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("System Prompt") {
                    TextEditor(text: $systemPrompt)
                        .font(.body)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 440, height: 500)
        .onAppear {
            if let existing {
                name = existing.name
                systemPrompt = existing.systemPrompt
                icon = existing.icon
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if var template = existing {
            template.name = trimmedName
            template.systemPrompt = systemPrompt
            template.icon = icon
            onSave(template)
        } else {
            let template = PromptTemplate(
                name: trimmedName,
                systemPrompt: systemPrompt,
                icon: icon
            )
            onSave(template)
        }
        dismiss()
    }
}

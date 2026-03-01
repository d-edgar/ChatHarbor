import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var sidebarExpanded: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            SidebarView(isExpanded: $sidebarExpanded)
                .environmentObject(serviceManager)

            Divider()

            // MARK: - Detail
            Group {
                if serviceManager.isLaunching {
                    SplashView()
                } else if serviceManager.services.isEmpty {
                    // No services yet — show onboarding catalog
                    OnboardingView()
                        .environmentObject(serviceManager)
                } else if let selectedId = serviceManager.selectedServiceId,
                   let service = serviceManager.enabledServices.first(where: { $0.id == selectedId }) {
                    WebContainerView(service: service)
                        .id(service.id)
                } else {
                    WelcomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            // Empty toolbar to get the native title bar area
        }
        .alert(
            "Switching to Workspace",
            isPresented: Binding(
                get: { serviceManager.pendingWorkspaceWarning != nil },
                set: { if !$0 { serviceManager.dismissWorkspaceWarning() } }
            )
        ) {
            Button("Continue") {
                serviceManager.confirmWorkspaceTransition()
            }
            .keyboardShortcut(.defaultAction)

            Button("Cancel", role: .cancel) {
                serviceManager.dismissWorkspaceWarning()
            }
        } message: {
            if let warning = serviceManager.pendingWorkspaceWarning {
                let clipboardNote = serviceManager.notificationSettings.workspaceGuardClearClipboard
                    ? "Your clipboard has been cleared."
                    : ""
                Text("You're switching to \(warning.targetServiceName), a workspace service. \(clipboardNote)")
            }
        }
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.8

    var body: some View {
        VStack(spacing: 20) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            Text("ChatHarbor")
                .font(.system(size: 36, weight: .bold, design: .rounded))

            Text("All your chats, one harbor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView()
                .scaleEffect(0.8)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(opacity)
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                opacity = 1.0
                scale = 1.0
            }
        }
    }
}

// MARK: - Onboarding View (first launch — pick your services)

struct OnboardingView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var selectedTemplateIds: Set<String> = []
    @State private var showingCustomSheet = false

    private var catalog: [(category: String, templates: [ServiceTemplate])] {
        ServiceCatalog.grouped(excluding: serviceManager.existingServiceIds)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image("ChatHarborLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

                Text("Welcome to ChatHarbor")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Choose the services you'd like to add, or add your own.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.bottom, 20)

            Divider()

            // Catalog grid
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(catalog, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.category.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 10) {
                                ForEach(group.templates) { template in
                                    CatalogCard(
                                        template: template,
                                        isSelected: selectedTemplateIds.contains(template.id)
                                    ) {
                                        if selectedTemplateIds.contains(template.id) {
                                            selectedTemplateIds.remove(template.id)
                                        } else {
                                            selectedTemplateIds.insert(template.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Add Custom Service...") {
                    showingCustomSheet = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                Spacer()

                if !selectedTemplateIds.isEmpty {
                    Text("\(selectedTemplateIds.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Add Selected") {
                    let templates = ServiceCatalog.all.filter { selectedTemplateIds.contains($0.id) }
                    serviceManager.addFromCatalog(templates)
                    selectedTemplateIds.removeAll()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(selectedTemplateIds.isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingCustomSheet) {
            AddCustomServiceSheet(isPresented: $showingCustomSheet)
                .environmentObject(serviceManager)
        }
    }
}

// MARK: - Catalog Card

struct CatalogCard: View {
    let template: ServiceTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: template.iconName)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(.quaternary)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 6, y: -6)
                }
            }

            Text(template.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(template.description)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Welcome View (shown when services exist but none selected)

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

            Text("Welcome to ChatHarbor")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Select a service from the sidebar to get started.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                KeyboardHint(key: "Cmd+1-9", label: "Switch services")
                KeyboardHint(key: "Cmd+R", label: "Reload")
                KeyboardHint(key: "Cmd+[", label: "Go back")
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keyboard Hint Chip

struct KeyboardHint: View {
    let key: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme
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
                } else if serviceManager.services.isEmpty || serviceManager.isOnboarding {
                    // No services yet or re-running setup — show onboarding wizard
                    OnboardingView()
                        .environmentObject(serviceManager)
                } else if let selectedId = serviceManager.selectedServiceId,
                   let service = serviceManager.enabledServices.first(where: { $0.id == selectedId }) {
                    WebContainerView(service: service)
                        .id(service.id)  // Keeps loading state per-service; WebView itself is pooled
                } else {
                    WelcomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(serviceManager.currentTheme.accentColor(for: colorScheme))
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

// MARK: - Onboarding View (multi-step setup wizard)

struct OnboardingView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentStep: SetupStep = .services
    @State private var selectedTemplateIds: Set<String> = []
    @State private var showingCustomSheet = false

    enum SetupStep: Int, CaseIterable {
        case services = 0
        case theme = 1
        case workspaceGuard = 2
        case privacyShield = 3

        var title: String {
            switch self {
            case .services: return "Choose Your Services"
            case .theme: return "Pick a Theme"
            case .workspaceGuard: return "Workspace Guard"
            case .privacyShield: return "Privacy Shield"
            }
        }

        var subtitle: String {
            switch self {
            case .services: return "Select the messaging services you use, or add your own."
            case .theme: return "Choose a color theme for ChatHarbor. You can change this anytime in Settings."
            case .workspaceGuard: return "Protect against clipboard cross-contamination between personal and work chats."
            case .privacyShield: return "Automatically blur your chats when your screen is being shared or recorded."
            }
        }

        var icon: String {
            switch self {
            case .services: return "bubble.left.and.bubble.right"
            case .theme: return "paintbrush"
            case .workspaceGuard: return "lock.shield"
            case .privacyShield: return "eye.slash"
            }
        }
    }

    private var catalog: [(category: String, templates: [ServiceTemplate])] {
        ServiceCatalog.grouped(excluding: serviceManager.existingServiceIds)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (shared across steps)
            VStack(spacing: 12) {
                Image("ChatHarborLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                Text(currentStep.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(currentStep.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                // Step indicators
                HStack(spacing: 8) {
                    ForEach(SetupStep.allCases, id: \.rawValue) { step in
                        HStack(spacing: 4) {
                            Image(systemName: step.icon)
                                .font(.system(size: 10))
                            if step == currentStep {
                                Text(step.title)
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .padding(.horizontal, step == currentStep ? 10 : 6)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(step == currentStep
                                      ? serviceManager.currentTheme.accentColor(for: colorScheme).opacity(0.15)
                                      : step.rawValue < currentStep.rawValue
                                        ? Color.green.opacity(0.1)
                                        : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(step == currentStep
                                        ? serviceManager.currentTheme.accentColor(for: colorScheme).opacity(0.4)
                                        : step.rawValue < currentStep.rawValue
                                          ? Color.green.opacity(0.3)
                                          : Color.gray.opacity(0.2),
                                        lineWidth: 1)
                        )
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Step content
            Group {
                switch currentStep {
                case .services:
                    servicesStepContent
                case .theme:
                    themeStepContent
                case .workspaceGuard:
                    workspaceGuardStepContent
                case .privacyShield:
                    privacyShieldStepContent
                }
            }

            Divider()

            // Bottom navigation bar
            HStack {
                if currentStep != .services {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if let prev = SetupStep(rawValue: currentStep.rawValue - 1) {
                                currentStep = prev
                            }
                        }
                    }
                    .controlSize(.regular)
                } else {
                    Button("Add Custom Service...") {
                        showingCustomSheet = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Spacer()

                if currentStep == .services && !selectedTemplateIds.isEmpty {
                    Text("\(selectedTemplateIds.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if currentStep == .privacyShield {
                    // Final step — finish button
                    Button("Get Started") {
                        // Add any selected services that haven't been added yet
                        if !selectedTemplateIds.isEmpty {
                            let templates = ServiceCatalog.all.filter { selectedTemplateIds.contains($0.id) }
                            serviceManager.addFromCatalog(templates)
                            selectedTemplateIds.removeAll()
                        }
                        serviceManager.finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(serviceManager.services.isEmpty && selectedTemplateIds.isEmpty)
                } else {
                    Button("Next") {
                        // On the services step, commit selections before advancing
                        if currentStep == .services && !selectedTemplateIds.isEmpty {
                            let templates = ServiceCatalog.all.filter { selectedTemplateIds.contains($0.id) }
                            serviceManager.addFromCatalog(templates)
                            selectedTemplateIds.removeAll()
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if let next = SetupStep(rawValue: currentStep.rawValue + 1) {
                                currentStep = next
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(currentStep == .services && selectedTemplateIds.isEmpty && serviceManager.services.isEmpty)
                }
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

    // MARK: - Step 1: Services

    private var servicesStepContent: some View {
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
    }

    // MARK: - Step 2: Theme

    private var themeStepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Appearance mode
                VStack(alignment: .leading, spacing: 10) {
                    Text("MODE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            SetupAppearancePill(
                                mode: mode,
                                isSelected: serviceManager.appearanceMode == mode
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    serviceManager.appearanceMode = mode
                                }
                            }
                        }
                    }
                }

                Divider()

                // Standard themes
                VStack(alignment: .leading, spacing: 10) {
                    Text("THEME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(ThemeCatalog.standardThemes) { theme in
                            ThemeCard(
                                theme: theme,
                                isSelected: serviceManager.selectedThemeId == theme.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    serviceManager.selectedThemeId = theme.id
                                }
                            }
                        }
                    }
                }

                Divider()

                // Seasonal themes
                VStack(alignment: .leading, spacing: 10) {
                    Text("SEASONAL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        ForEach(ThemeCatalog.seasonalThemes) { theme in
                            ThemeCard(
                                theme: theme,
                                isSelected: serviceManager.selectedThemeId == theme.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    serviceManager.selectedThemeId = theme.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Step 3: Workspace Guard

    private var workspaceGuardStepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Explanation card
                HStack(spacing: 14) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 28))
                        .foregroundStyle(serviceManager.currentTheme.accentColor(for: colorScheme))
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("What is Workspace Guard?")
                            .font(.system(size: 13, weight: .semibold))
                        Text("When you switch from a personal or social chat to a workspace service, ChatHarbor can automatically clear your clipboard and show a warning — helping prevent accidentally pasting personal content into work conversations.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary.opacity(0.3))
                )

                Divider()

                // Toggle
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Workspace Guard", isOn: $serviceManager.notificationSettings.workspaceGuardEnabled)
                        .font(.system(size: 13, weight: .medium))

                    Group {
                        Toggle("Clear Clipboard on Transition", isOn: $serviceManager.notificationSettings.workspaceGuardClearClipboard)
                            .font(.system(size: 13))

                        Toggle("Show Warning Banner", isOn: $serviceManager.notificationSettings.workspaceGuardShowWarning)
                            .font(.system(size: 13))
                    }
                    .disabled(!serviceManager.notificationSettings.workspaceGuardEnabled)
                    .opacity(serviceManager.notificationSettings.workspaceGuardEnabled ? 1.0 : 0.5)
                    .padding(.leading, 20)
                }

                Divider()

                // Workspace category picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("WORKSPACE CATEGORIES")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("Which categories should be treated as workspace zones?")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    ForEach(serviceManager.categories, id: \.self) { category in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: {
                                    serviceManager.notificationSettings.workspaceCategories.contains(category)
                                },
                                set: { on in
                                    if on {
                                        serviceManager.notificationSettings.workspaceCategories.insert(category)
                                    } else {
                                        serviceManager.notificationSettings.workspaceCategories.remove(category)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                            Text(category)
                                .font(.system(size: 13))

                            let count = serviceManager.services(inCategory: category).count
                            if count > 0 {
                                Text("(\(count) service\(count == 1 ? "" : "s"))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .disabled(!serviceManager.notificationSettings.workspaceGuardEnabled)
                .opacity(serviceManager.notificationSettings.workspaceGuardEnabled ? 1.0 : 0.5)

                // Skip hint
                if !serviceManager.notificationSettings.workspaceGuardEnabled {
                    Text("You can skip this and enable it later in Settings > Security.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Step 4: Privacy Shield

    private var privacyShieldStepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Explanation card
                HStack(spacing: 14) {
                    Image(systemName: "eye.slash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(serviceManager.currentTheme.accentColor(for: colorScheme))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("What is Privacy Shield?")
                            .font(.system(size: 13, weight: .semibold))
                        Text("When ChatHarbor detects that your screen is being shared, recorded, or remotely viewed, it automatically blurs your chat content and shows a friendly notice — keeping sensitive conversations private during presentations and calls.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary.opacity(0.3))
                )

                Divider()

                // Toggle
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable Privacy Shield", isOn: $serviceManager.notificationSettings.privacyShieldEnabled)
                        .font(.system(size: 13, weight: .medium))

                    Group {
                        Toggle("Blur Chat Content", isOn: $serviceManager.notificationSettings.privacyShieldBlurContent)
                            .font(.system(size: 13))

                        Toggle("Show Warning Overlay", isOn: $serviceManager.notificationSettings.privacyShieldShowWarning)
                            .font(.system(size: 13))
                    }
                    .disabled(!serviceManager.notificationSettings.privacyShieldEnabled)
                    .opacity(serviceManager.notificationSettings.privacyShieldEnabled ? 1.0 : 0.5)
                    .padding(.leading, 20)
                }

                Divider()

                // How it works
                VStack(alignment: .leading, spacing: 8) {
                    Text("HOW IT WORKS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Detects screen sharing apps (Zoom, Teams, etc.)", systemImage: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Label("Detects screen recording and remote desktop sessions", systemImage: "record.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Label("No data leaves your Mac — detection is 100% local", systemImage: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!serviceManager.notificationSettings.privacyShieldEnabled)
                .opacity(serviceManager.notificationSettings.privacyShieldEnabled ? 1.0 : 0.5)

                // Skip hint
                if !serviceManager.notificationSettings.privacyShieldEnabled {
                    Text("You can skip this and enable it later in Settings > Security.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Setup Appearance Mode Pill

struct SetupAppearancePill: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        serviceManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: mode == .auto ? "circle.lefthalf.filled" : mode == .light ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 11))
                Text(mode.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? accent.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? accent : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalog Card

struct CatalogCard: View {
    let template: ServiceTemplate
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        serviceManager.currentTheme.accentColor(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: template.iconName)
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        isSelected
                            ? AnyShapeStyle(accent)
                            : AnyShapeStyle(.quaternary)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, accent)
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
                .fill(isSelected ? accent.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? accent : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
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

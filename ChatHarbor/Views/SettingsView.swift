import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager

    var body: some View {
        TabView {
            ServicesSettingsView()
                .environmentObject(serviceManager)
                .tabItem {
                    Label("Services", systemImage: "list.bullet")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - Services Tab

struct ServicesSettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(ServiceCategory.allCases, id: \.self) { category in
                    let servicesInCategory = serviceManager.services.filter { $0.category == category }
                    if !servicesInCategory.isEmpty {
                        Section(category.rawValue) {
                            ForEach(servicesInCategory) { service in
                                HStack(spacing: 12) {
                                    Image(systemName: service.iconName)
                                        .font(.body)
                                        .frame(width: 22)
                                        .foregroundStyle(.secondary)
                                    Text(service.name)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { service.isEnabled },
                                        set: { _ in serviceManager.toggleService(service) }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)

                                    if service.id.hasPrefix("custom-") {
                                        Button(role: .destructive) {
                                            serviceManager.removeService(service)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Add Custom Service...") {
                    showingAddSheet = true
                }
                .controlSize(.small)
                .padding(12)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCustomServiceSheet(isPresented: $showingAddSheet)
                .environmentObject(serviceManager)
        }
    }
}

// MARK: - Appearance Tab

struct AppearanceSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintbrush.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Appearance")
                .font(.headline)

            Text("ChatHarbor automatically follows your macOS appearance settings. Switch between Light and Dark mode in System Settings > Appearance.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white)
                        .frame(width: 60, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    Text("Light")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black)
                        .frame(width: 60, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    Text("Dark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Add Custom Service Sheet

struct AddCustomServiceSheet: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var urlString = "https://"
    @State private var showingError = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Service")
                .font(.headline)

            TextField("Service Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("URL (https://...)", text: $urlString)
                .textFieldStyle(.roundedBorder)

            if showingError {
                Text("Please enter a valid name and URL starting with http:// or https://")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                          let url = URL(string: urlString),
                          url.scheme == "http" || url.scheme == "https",
                          url.host != nil else {
                        showingError = true
                        return
                    }
                    serviceManager.addCustomService(name: name, urlString: urlString)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - About Tab

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("ChatHarborLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            Text("ChatHarbor")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A lightweight, native macOS chat aggregator.\nBuilt with SwiftUI and WebKit.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("View on GitHub", destination: URL(string: "https://github.com/d-edgar/ChatHarbor")!)
                .padding(.top, 4)

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

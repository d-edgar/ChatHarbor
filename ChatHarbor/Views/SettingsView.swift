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

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 350)
    }
}

// MARK: - Services Tab

struct ServicesSettingsView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingAddSheet = false

    var body: some View {
        VStack {
            List {
                ForEach(serviceManager.services) { service in
                    HStack {
                        Image(systemName: service.iconName)
                            .frame(width: 24)
                        Text(service.name)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { service.isEnabled },
                            set: { _ in serviceManager.toggleService(service) }
                        ))
                        .labelsHidden()

                        // Only allow removing custom services
                        if service.id.hasPrefix("custom-") {
                            Button(role: .destructive) {
                                serviceManager.removeService(service)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .onMove { source, destination in
                    serviceManager.moveService(from: source, to: destination)
                }
            }

            HStack {
                Spacer()
                Button("Add Custom Service...") {
                    showingAddSheet = true
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCustomServiceSheet(isPresented: $showingAddSheet)
                .environmentObject(serviceManager)
        }
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
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("ChatHarbor")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A lightweight, native macOS chat aggregator.")
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

import SwiftUI

struct ChatHarborCommands: Commands {
    @ObservedObject var serviceManager: ServiceManager

    var body: some Commands {
        CommandMenu("Services") {
            ForEach(Array(serviceManager.enabledServices.enumerated().prefix(9)), id: \.element.id) { index, service in
                Button("Switch to \(service.name)") {
                    serviceManager.selectService(service.id)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }

            Divider()

            Button("Reload Current Service") {
                if let selectedId = serviceManager.selectedServiceId {
                    NotificationCenter.default.post(
                        name: .reloadService,
                        object: nil,
                        userInfo: ["serviceId": selectedId]
                    )
                }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Go Back") {
                if let selectedId = serviceManager.selectedServiceId {
                    NotificationCenter.default.post(
                        name: .goBackService,
                        object: nil,
                        userInfo: ["serviceId": selectedId]
                    )
                }
            }
            .keyboardShortcut("[", modifiers: .command)
        }

        CommandMenu("Privacy") {
            Button(ScreenShareDetector.shared.isManuallyEngaged
                   ? "Disengage Privacy Shield"
                   : "Engage Privacy Shield") {
                ScreenShareDetector.shared.toggleManualEngagement()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}

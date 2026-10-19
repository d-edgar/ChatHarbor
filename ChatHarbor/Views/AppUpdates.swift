import SwiftUI
import Combine
import Sparkle

@MainActor
final class AppUpdates: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    @Published private(set) var automaticallyChecks = true

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
            updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecks)
    }

    func check() { controller.checkForUpdates(nil) }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updates: AppUpdates

    var body: some View {
        Button("Check for Updates…", action: updates.check)
            .disabled(!updates.canCheck)
    }
}

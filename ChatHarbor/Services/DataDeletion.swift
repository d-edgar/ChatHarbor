import AppKit
import CoreData
import SwiftData

struct ChatDeletionPause {
    private(set) var until: Date?

    func isActive(at now: Date = Date()) -> Bool {
        until.map { now < $0 } ?? false
    }

    mutating func start(at now: Date = Date()) {
        until = now.addingTimeInterval(300)
    }
}

@MainActor
enum DataDeletion {
    private static var pause = ChatDeletionPause()

    static func confirm(name: String, detail: String, isChat: Bool = false) -> Bool {
        if isChat && pause.isActive() { return true }
        let alert = NSAlert()
        alert.messageText = "Delete \u{201c}\(name)\u{201d}?"
        alert.informativeText = detail + " This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        if isChat {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Skip chat confirmations for 5 minutes"
        }
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        if isChat && alert.suppressionButton?.state == .on { pause.start() }
        return true
    }

    @discardableResult
    static func delete<T: PersistentModel>(_ item: T, in context: ModelContext) -> Bool {
        do {
            // Save unrelated edits first so a failed deletion can roll back safely.
            try context.save()
            context.delete(item)
            do { try context.save() }
            catch { context.rollback(); throw error }
            return true
        } catch {
            showError(error)
            return false
        }
    }

    static func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

/// Runs before opening the store so no live response can recreate deleted records.
enum LocalDataReset {
    static let pendingKey = "deleteAllDataOnNextLaunch"

    static func perform(storeURL: URL, defaults: UserDefaults, domain: String,
                        cacheURLs: [URL], deleteCredentials: () throws -> Void) throws {
        guard defaults.bool(forKey: pendingKey) else { return }
        try deleteCredentials()
        if FileManager.default.fileExists(atPath: storeURL.path) {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
            try coordinator.destroyPersistentStore(at: storeURL, type: .sqlite)
        }
        let storeFiles = [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"),
                          URL(fileURLWithPath: storeURL.path + "-shm")]
        for url in storeFiles + cacheURLs where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // Clear the durable request last; a partial failure must retry before the app opens.
        defaults.removePersistentDomain(forName: domain)
        guard defaults.synchronize() else {
            defaults.set(true, forKey: pendingKey)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

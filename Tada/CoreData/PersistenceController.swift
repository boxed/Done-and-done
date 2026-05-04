//
//  PersistenceController.swift
//  Tada
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext

        // Create sample data
        let list = TodoList(context: viewContext)
        list.id = UUID()
        list.name = "Sample List"
        list.creationDate = Date()
        list.order = 0

        for i in 0..<5 {
            let item = TodoItem(context: viewContext)
            item.id = UUID()
            item.text = "Sample Item \(i + 1)"
            item.creationTime = Date()
            item.order = Int32(i)
            item.list = list
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return controller
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Tada")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description found")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
            description.cloudKitContainerOptions = nil
        } else {
            // Configure CloudKit
            let cloudKitOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.net.kodare.Tada"
            )
            description.cloudKitContainerOptions = cloudKitOptions

            // Enable persistent history tracking for CloudKit sync
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Set up undo manager
        container.viewContext.undoManager = UndoManager()

        // Set up query generation for consistent reads
        do {
            try container.viewContext.setQueryGenerationFrom(.current)
        } catch {
            print("Failed to set query generation: \(error)")
        }
    }

    // MARK: - CloudKit Sharing

    func share(_ list: TodoList, completion: @escaping (CKShare?, Error?) -> Void) {
        let container = self.container

        container.share([list], to: nil) { objectIDs, share, ckContainer, error in
            if let error = error {
                completion(nil, error)
                return
            }

            guard let share = share else {
                completion(nil, NSError(domain: "Tada", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create share"]))
                return
            }

            share[CKShare.SystemFieldKey.title] = list.name
            completion(share, nil)
        }
    }

    func fetchShare(for list: TodoList) -> CKShare? {
        guard let shares = try? container.fetchShares(matching: [list.objectID]) else {
            return nil
        }
        return shares[list.objectID]
    }

    func isShared(_ list: TodoList) -> Bool {
        fetchShare(for: list) != nil
    }

    // MARK: - Cleanup Old Completed Items

    func deleteOldCompletedItems() {
        let context = container.viewContext
        let request: NSFetchRequest<TodoItem> = TodoItem.fetchRequest()
        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        request.predicate = NSPredicate(format: "completionTime != nil AND completionTime < %@", cutoffDate as NSDate)

        do {
            let oldItems = try context.fetch(request)
            for item in oldItems {
                context.delete(item)
            }
            if !oldItems.isEmpty {
                try context.save()
            }
        } catch {
            print("Failed to delete old completed items: \(error)")
        }
    }

    // MARK: - Reset Sync

    /// Destroys and recreates the local persistent store, forcing a full re-sync from CloudKit.
    /// Use when sync gets stuck with "Change Token Expired" errors.
    func resetCloudKitSync() {
        print("Resetting CloudKit sync")
        guard let description = container.persistentStoreDescriptions.first,
              let storeURL = description.url else {
            print("No store URL found")
            return
        }

        let coordinator = container.persistentStoreCoordinator

        // Remove existing stores
        for store in coordinator.persistentStores {
            do {
                try coordinator.remove(store)
            } catch {
                print("Failed to remove store: \(error)")
            }
        }

        // Delete the store files
        let fileManager = FileManager.default
        let storePath = storeURL.path
        for suffix in ["", "-wal", "-shm"] {
            let fileURL = URL(fileURLWithPath: storePath + suffix)
            try? fileManager.removeItem(at: fileURL)
        }

        // Also delete the CloudKit metadata
        let ckMetadataURL = storeURL.deletingLastPathComponent().appendingPathComponent("ckAssets")
        try? fileManager.removeItem(at: ckMetadataURL)

        // Reload the store — CloudKit will do a full import
        container.loadPersistentStores { _, error in
            if let error = error {
                print("Failed to reload store after reset: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save Context

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

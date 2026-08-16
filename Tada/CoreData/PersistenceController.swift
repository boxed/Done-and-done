//
//  PersistenceController.swift
//  Tada
//

import CoreData
import CloudKit

/// The local store. Syncing is no longer Core Data's job: `CloudKitManager` owns that, driving
/// CKSyncEngine against records mapped from these entities.
struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

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

    let isInMemory: Bool

    /// Loaded once and shared. Building a second NSPersistentContainer normally parses the model
    /// again, and two copies of the same model make Core Data unable to match an entity to its
    /// generated class ("Failed to find a unique match for an NSEntityDescription").
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "Tada", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to load the Tada managed object model")
        }
        return model
    }()

    init(inMemory: Bool = false) {
        isInMemory = inMemory
        container = NSPersistentContainer(name: "Tada", managedObjectModel: Self.managedObjectModel)

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store description found")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // The store was created by NSPersistentCloudKitContainer, which turned history
            // tracking on. It has to stay on: Core Data refuses to open a store that once had
            // history tracking without it.
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

        // Set up query generation for consistent reads. In-memory stores don't support it.
        if !inMemory {
            do {
                try container.viewContext.setQueryGenerationFrom(.current)
            } catch {
                print("Failed to set query generation: \(error)")
            }
        }

        if !inMemory {
            backfillSyncIdentifiers()
        }
    }

    // MARK: - Sync Identifiers

    /// Every record needs a stable name to sync under, and every list needs a zone to live in.
    /// Both are optional in the model — CloudKit imports could leave `id` nil — so repair them
    /// before the sync engine ever looks at the data.
    func backfillSyncIdentifiers() {
        let context = container.viewContext
        var changed = false

        let listRequest: NSFetchRequest<TodoList> = TodoList.fetchRequest()
        let itemRequest: NSFetchRequest<TodoItem> = TodoItem.fetchRequest()

        do {
            for list in try context.fetch(listRequest) {
                if list.id == nil {
                    list.id = UUID()
                    changed = true
                }
                if list.zoneName == nil, let id = list.id {
                    list.zoneName = CloudKitManager.zoneName(forListID: id)
                    changed = true
                }
            }
            for item in try context.fetch(itemRequest) where item.id == nil {
                item.id = UUID()
                changed = true
            }
            if changed {
                try context.save()
            }
        } catch {
            print("Failed to backfill sync identifiers: \(error)")
        }
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

//
//  CloudKitManager+Records.swift
//  Tada
//
//  Mapping between Core Data objects and CKRecords, and turning local saves into pending
//  sync engine changes.
//

import Foundation
import CloudKit
import CoreData

extension CloudKitManager {
    enum RecordType {
        static let list = "TodoList"
        static let item = "TodoItem"
    }

    private enum ListKey {
        static let name = "name"
        static let order = "order"
        // Not "creationDate": CKRecord reserves that name, and assigning to a reserved key
        // throws NSInvalidArgumentException rather than failing gracefully.
        static let creationDate = "listCreationDate"
    }

    /// Keys CKRecord owns. Using any of them as a custom field crashes on assignment.
    static let reservedRecordKeys: Set<String> = [
        "recordID", "recordType", "creationDate", "creatorUserRecordID",
        "modificationDate", "lastModifiedUserRecordID", "recordChangeTag",
        "parent", "share"
    ]

    private enum ItemKey {
        static let text = "text"
        static let order = "order"
        static let creationTime = "creationTime"
        static let completionTime = "completionTime"
        static let startedTime = "startedTime"
        static let isHidden = "isHidden"
        static let listID = "listID"
    }

    // MARK: - Local Change Tracking

    /// The views save `viewContext` directly, so the only reliable place to notice changes is the
    /// context notifications. Deletions have to be captured before the save, while the objects can
    /// still be read.
    func observeLocalChanges() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: .NSManagedObjectContextWillSave,
            object: viewContextForObservation,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let context = notification.object as? NSManagedObjectContext else { return }
                self.captureDeletions(in: context)
            }
        }

        center.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: viewContextForObservation,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let userInfo = notification.userInfo else { return }
                self.enqueueChanges(userInfo: userInfo)
                self.flushCapturedDeletions()
            }
        }
    }

    private func captureDeletions(in context: NSManagedObjectContext) {
        for object in context.deletedObjects {
            switch object {
            case let list as TodoList:
                if let zoneID = zoneID(for: list) {
                    // The list owns its zone, so deleting the list deletes the zone — which takes
                    // its items with it and avoids a per-item delete storm.
                    pendingZoneDeletions.append(zoneID)
                }
            case let item as TodoItem:
                if let recordID = recordID(for: item) {
                    pendingRecordDeletions.append(recordID)
                }
            default:
                break
            }
        }
    }

    private func flushCapturedDeletions() {
        for zoneID in pendingZoneDeletions {
            engineForZone(ownerName: zoneID.ownerName)?
                .state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
        }
        for recordID in pendingRecordDeletions {
            engineForZone(ownerName: recordID.zoneID.ownerName)?
                .state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        }
        pendingZoneDeletions.removeAll()
        pendingRecordDeletions.removeAll()
    }

    private func enqueueChanges(userInfo: [AnyHashable: Any]) {
        guard !isApplyingRemoteChanges else { return }

        let inserted = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        let updated = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []

        for object in inserted.union(updated) {
            enqueueSave(for: object, createZone: inserted.contains(object))
        }
    }

    func enqueueSave(for object: NSManagedObject, createZone: Bool) {
        switch object {
        case let list as TodoList:
            guard let zoneID = zoneID(for: list), let recordID = recordID(for: list) else { return }
            let engine = engineForZone(ownerName: zoneID.ownerName)
            if createZone {
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            }
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case let item as TodoItem:
            guard let recordID = recordID(for: item) else { return }
            engineForZone(ownerName: recordID.zoneID.ownerName)?
                .state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        default:
            break
        }
    }

    /// Anything the server has never acknowledged has no stored system fields, so this finds
    /// everything that still needs uploading: data that predates the sync engine, edits made
    /// while offline, and saves that happened before the observers were installed. Running it on
    /// every launch means a missed save repairs itself instead of never syncing again.
    func enqueueUnsyncedObjects() {
        let context = viewContextForObservation

        let listRequest: NSFetchRequest<TodoList> = TodoList.fetchRequest()
        listRequest.predicate = NSPredicate(format: "systemFields == nil")

        let itemRequest: NSFetchRequest<TodoItem> = TodoItem.fetchRequest()
        itemRequest.predicate = NSPredicate(format: "systemFields == nil")

        do {
            for list in try context.fetch(listRequest) {
                enqueueSave(for: list, createZone: true)
            }
            for item in try context.fetch(itemRequest) {
                enqueueSave(for: item, createZone: false)
            }
        } catch {
            print("Failed to enqueue unsynced objects: \(error)")
        }
    }

    func enqueueAllLocalData() {
        let context = viewContextForObservation
        do {
            for list in try context.fetch(TodoList.fetchRequest()) as [TodoList] {
                enqueueSave(for: list, createZone: true)
            }
            for item in try context.fetch(TodoItem.fetchRequest()) as [TodoItem] {
                enqueueSave(for: item, createZone: false)
            }
        } catch {
            print("Failed to enqueue local data: \(error)")
        }
    }

    // MARK: - Identity

    func zoneID(for list: TodoList) -> CKRecordZone.ID? {
        guard let id = list.id else { return nil }
        let name = list.zoneName ?? Self.zoneName(forListID: id)
        return CKRecordZone.ID(
            zoneName: name,
            ownerName: list.zoneOwnerName ?? CKCurrentUserDefaultName
        )
    }

    func recordID(for list: TodoList) -> CKRecord.ID? {
        guard let id = list.id, let zoneID = zoneID(for: list) else { return nil }
        return CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    func recordID(for item: TodoItem) -> CKRecord.ID? {
        guard let id = item.id, let list = item.list, let zoneID = zoneID(for: list) else { return nil }
        return CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    // MARK: - Core Data to CKRecord

    func record(for recordID: CKRecord.ID) -> CKRecord? {
        if let list = findList(recordName: recordID.recordName) {
            return makeRecord(for: list, recordID: recordID)
        }
        if let item = findItem(recordName: recordID.recordName) {
            return makeRecord(for: item, recordID: recordID)
        }
        return nil
    }

    func makeRecord(for list: TodoList, recordID: CKRecord.ID) -> CKRecord {
        let record = existingRecord(from: list.systemFields) ?? CKRecord(recordType: RecordType.list, recordID: recordID)
        record[ListKey.name] = list.name
        record[ListKey.order] = Int64(list.order)
        record[ListKey.creationDate] = list.creationDate
        return record
    }

    func makeRecord(for item: TodoItem, recordID: CKRecord.ID) -> CKRecord {
        let record = existingRecord(from: item.systemFields) ?? CKRecord(recordType: RecordType.item, recordID: recordID)
        record[ItemKey.text] = item.text
        record[ItemKey.order] = Int64(item.order)
        record[ItemKey.creationTime] = item.creationTime
        record[ItemKey.completionTime] = item.completionTime
        record[ItemKey.startedTime] = item.startedTime
        record[ItemKey.isHidden] = item.isHidden ? Int64(1) : Int64(0)
        record[ItemKey.listID] = item.list?.id?.uuidString
        return record
    }

    /// Rebuilding from the stored system fields keeps the server's change tag, which is what lets
    /// an update be recognised as an update instead of a conflicting create.
    private func existingRecord(from data: Data?) -> CKRecord? {
        guard let data else { return nil }
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = true
            let record = CKRecord(coder: unarchiver)
            unarchiver.finishDecoding()
            return record
        } catch {
            return nil
        }
    }

    func encodedSystemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    func storeSystemFields(from record: CKRecord) {
        if let list = findList(recordName: record.recordID.recordName) {
            list.systemFields = encodedSystemFields(of: record)
        } else if let item = findItem(recordName: record.recordID.recordName) {
            item.systemFields = encodedSystemFields(of: record)
        }
    }

    // MARK: - CKRecord to Core Data

    func upsertLocalObject(from record: CKRecord) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        switch record.recordType {
        case RecordType.list:
            upsertList(from: record)
        case RecordType.item:
            upsertItem(from: record)
        default:
            break
        }
    }

    private func upsertList(from record: CKRecord) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let list = findList(recordName: record.recordID.recordName) ?? TodoList(context: viewContextForObservation)
        list.id = id
        list.name = record[ListKey.name] as? String ?? list.name ?? ""
        list.order = Int32(record[ListKey.order] as? Int64 ?? Int64(list.order))
        list.creationDate = record[ListKey.creationDate] as? Date ?? list.creationDate
        list.zoneName = record.recordID.zoneID.zoneName
        list.zoneOwnerName = record.recordID.zoneID.ownerName
        list.systemFields = encodedSystemFields(of: record)

        // Arriving from a zone someone else owns means this list was shared with us, which is
        // what the badge in the sidebar is for.
        if record.recordID.zoneID.ownerName != CKCurrentUserDefaultName {
            list.isShared = true
        }
    }

    private func upsertItem(from record: CKRecord) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let item = findItem(recordName: record.recordID.recordName) ?? TodoItem(context: viewContextForObservation)
        item.id = id
        item.text = record[ItemKey.text] as? String ?? item.text ?? ""
        item.order = Int32(record[ItemKey.order] as? Int64 ?? Int64(item.order))
        item.creationTime = record[ItemKey.creationTime] as? Date ?? item.creationTime
        item.completionTime = record[ItemKey.completionTime] as? Date
        item.startedTime = record[ItemKey.startedTime] as? Date
        item.isHidden = (record[ItemKey.isHidden] as? Int64 ?? 0) == 1
        item.systemFields = encodedSystemFields(of: record)

        // The list record may not have arrived yet — records within a zone come in no particular
        // order — so stand up a placeholder the list record will fill in when it lands.
        if let listIDString = record[ItemKey.listID] as? String,
           let listID = UUID(uuidString: listIDString) {
            if let list = findList(recordName: listIDString) {
                item.list = list
            } else {
                let placeholder = TodoList(context: viewContextForObservation)
                placeholder.id = listID
                placeholder.name = ""
                placeholder.zoneName = record.recordID.zoneID.zoneName
                placeholder.zoneOwnerName = record.recordID.zoneID.ownerName
                item.list = placeholder
            }
        }
    }

    func deleteLocalObject(recordID: CKRecord.ID, recordType: CKRecord.RecordType) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        if recordType == RecordType.list, let list = findList(recordName: recordID.recordName) {
            viewContextForObservation.delete(list)
        } else if let item = findItem(recordName: recordID.recordName) {
            viewContextForObservation.delete(item)
        }
    }

    func deleteLocalList(inZone zoneID: CKRecordZone.ID) {
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        let request: NSFetchRequest<TodoList> = TodoList.fetchRequest()
        request.predicate = NSPredicate(format: "zoneName == %@", zoneID.zoneName)
        if let lists = try? viewContextForObservation.fetch(request) {
            for list in lists {
                viewContextForObservation.delete(list)
            }
        }
        saveLocalChangesQuietly()
    }

    /// Saving remote changes must not bounce straight back out as local changes.
    func saveLocalChangesQuietly() {
        let context = viewContextForObservation
        guard context.hasChanges else { return }
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }
        do {
            try context.save()
        } catch {
            print("Failed to save fetched changes: \(error)")
        }
    }

    // MARK: - Lookups

    func findList(recordName: String) -> TodoList? {
        guard let id = UUID(uuidString: recordName) else { return nil }
        let request: NSFetchRequest<TodoList> = TodoList.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContextForObservation.fetch(request).first
    }

    func findItem(recordName: String) -> TodoItem? {
        guard let id = UUID(uuidString: recordName) else { return nil }
        let request: NSFetchRequest<TodoItem> = TodoItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? viewContextForObservation.fetch(request).first
    }
}

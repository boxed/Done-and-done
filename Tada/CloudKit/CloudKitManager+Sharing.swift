//
//  CloudKitManager+Sharing.swift
//  Tada
//
//  Zone-wide sharing. Each list already lives in its own record zone, so sharing a list means
//  sharing its zone — one CKShare per zone covers the list and every item in it, with no parent
//  references to maintain.
//

import Foundation
import CloudKit
import CoreData

extension CloudKitManager {
    enum SharingError: LocalizedError {
        case listNotSyncable
        case shareNotSaved

        var errorDescription: String? {
            switch self {
            case .listNotSyncable:
                return "This list can't be shared until it has finished syncing."
            case .shareNotSaved:
                return "iCloud didn't accept the share."
            }
        }
    }

    /// Returns the share for a list, creating one if it doesn't exist yet. The zone must exist on
    /// the server first, so this pushes any pending changes before sharing.
    func share(_ list: TodoList) async throws -> CKShare {
        guard let zoneID = zoneID(for: list) else { throw SharingError.listNotSyncable }

        // A zone-wide share can only be created for a zone the server knows about.
        try await privateEngineSendChanges()

        if let existing = try await fetchShare(forZoneID: zoneID) {
            return existing
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = list.name

        let result = try await container.privateCloudDatabase.modifyRecords(
            saving: [share],
            deleting: [],
            savePolicy: .changedKeys
        )

        guard let saveResult = result.saveResults[share.recordID],
              case .success(let savedRecord) = saveResult,
              let savedShare = savedRecord as? CKShare else {
            throw SharingError.shareNotSaved
        }

        list.isShared = true
        list.cloudKitShareRecordID = savedShare.recordID.recordName
        PersistenceController.shared.save()

        return savedShare
    }

    func fetchShare(forZoneID zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let database = zoneID.ownerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase

        // `share` is only populated on zones fetched from the server, and only when a zone-wide
        // share actually exists.
        let zone = try await database.recordZone(for: zoneID)
        guard let reference = zone.share else { return nil }
        let record = try await database.record(for: reference.recordID)
        return record as? CKShare
    }

    /// Called when the user opens a share link. Accepting puts the zone in our shared database,
    /// then the shared engine pulls its contents.
    func acceptShare(metadata: CKShare.Metadata) async {
        beginSharingOperation()
        do {
            _ = try await container.accept([metadata])
            await refresh()
        } catch {
            reportSharingFailure(error)
        }
    }

    /// After a share is accepted or a participant is removed, the list's shared state may have
    /// changed on the server; reflect it locally.
    func refreshSharedState(for list: TodoList) async {
        guard let zoneID = zoneID(for: list) else { return }
        do {
            let share = try await fetchShare(forZoneID: zoneID)
            list.isShared = share != nil
            list.cloudKitShareRecordID = share?.recordID.recordName
            PersistenceController.shared.save()
        } catch {
            // A missing zone just means nothing has synced yet — not worth surfacing.
            print("Could not refresh shared state: \(error)")
        }
    }
}

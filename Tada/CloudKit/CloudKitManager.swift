//
//  CloudKitManager.swift
//  Tada
//

import Foundation
import CloudKit
import CoreData
import Combine

/// Owns syncing. Each list lives in its own record zone so it can be shared independently, and
/// there is one CKSyncEngine per database: the private one for lists we own, the shared one for
/// lists other people have shared with us.
///
/// Unlike NSPersistentCloudKitContainer, every step here is observable — `fetchChanges()` is a
/// real awaitable round trip, so the UI can show what is actually happening instead of guessing.
@Observable
@MainActor
final class CloudKitManager: NSObject, CKSyncEngineDelegate {
    static let shared = CloudKitManager()

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)

        var shouldShowIcon: Bool {
            switch self {
            case .syncing, .error:
                return true
            case .idle, .success:
                return false
            }
        }
    }

    static let containerIdentifier = "iCloud.net.kodare.Tada"

    static func zoneName(forListID id: UUID) -> String {
        "list-\(id.uuidString)"
    }

    var syncStatus: SyncStatus = .idle
    var lastSyncDate: Date?
    var accountStatus: CKAccountStatus = .couldNotDetermine

    @ObservationIgnored let container = CKContainer(identifier: CloudKitManager.containerIdentifier)
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    @ObservationIgnored private var inFlightOperations = 0

    /// Set while writing fetched records into Core Data, so the resulting save isn't mistaken for
    /// a local edit and sent straight back to the server.
    @ObservationIgnored var isApplyingRemoteChanges = false

    /// Deletions have to be read before the context saves, but can only be enqueued after.
    @ObservationIgnored var pendingZoneDeletions: [CKRecordZone.ID] = []
    @ObservationIgnored var pendingRecordDeletions: [CKRecord.ID] = []

    var viewContextForObservation: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard privateEngine == nil else { return }

        privateEngine = makeEngine(for: container.privateCloudDatabase, scope: .private)
        sharedEngine = makeEngine(for: container.sharedCloudDatabase, scope: .shared)

        observeLocalChanges()
        enqueueUnsyncedObjects()

        Task {
            await checkAccountStatus()
        }
    }

    private func makeEngine(for database: CKDatabase, scope: CKDatabase.Scope) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadStateSerialization(for: scope),
            delegate: self
        )
        configuration.automaticallySync = true
        return CKSyncEngine(configuration)
    }

    /// Records in a zone owned by someone else belong to the shared database.
    func engineForZone(ownerName: String?) -> CKSyncEngine? {
        if let ownerName, ownerName != CKCurrentUserDefaultName {
            return sharedEngine
        }
        return privateEngine
    }

    // MARK: - Manual Sync

    /// A real round trip, so pull-to-refresh reflects actual work. Fetching first then sending
    /// means the caller sees remote changes before their own are pushed.
    func refresh() async {
        guard let privateEngine else { return }
        beginOperation()
        defer { endOperation(error: nil) }

        do {
            try await privateEngine.fetchChanges()
            try await sharedEngine?.fetchChanges()
            try await privateEngine.sendChanges()
            try await sharedEngine?.sendChanges()
            lastSyncDate = Date()
        } catch {
            endOperation(error: error)
        }
    }

    func triggerSync() {
        Task { await refresh() }
    }

    /// Sharing needs the zone to exist server-side, so pending changes must land first.
    func privateEngineSendChanges() async throws {
        guard let privateEngine else { return }
        try await privateEngine.sendChanges()
    }

    func beginSharingOperation() {
        beginOperation()
    }

    func reportSharingFailure(_ error: Error) {
        endOperation(error: error)
    }

    func checkAccountStatus() async {
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            print("Failed to get account status: \(error)")
        }
    }

    // MARK: - Status Bookkeeping

    private func beginOperation() {
        inFlightOperations += 1
        syncStatus = .syncing
    }

    private func endOperation(error: Error?) {
        inFlightOperations = max(0, inFlightOperations - 1)

        if let error {
            syncStatus = .error(error.localizedDescription)
            return
        }
        guard inFlightOperations == 0 else { return }
        if case .error = syncStatus { return }

        syncStatus = .success
        lastSyncDate = Date()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if syncStatus == .success {
                syncStatus = .idle
            }
        }
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            save(update.stateSerialization, for: syncEngine.database.databaseScope)

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions {
                deleteLocalList(inZone: deletion.zoneID)
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                upsertLocalObject(from: modification.record)
            }
            for deletion in changes.deletions {
                deleteLocalObject(recordID: deletion.recordID, recordType: deletion.recordType)
            }
            saveLocalChangesQuietly()

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                storeSystemFields(from: record)
            }
            for failure in sent.failedRecordSaves {
                handleFailedSave(failure, syncEngine: syncEngine)
            }
            saveLocalChangesQuietly()

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                print("Zone save failed: \(failure.zone.zoneID) \(failure.error)")
            }

        case .willFetchChanges, .willSendChanges:
            beginOperation()

        case .didFetchChanges, .didSendChanges:
            endOperation(error: nil)

        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        guard !pending.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            await MainActor.run {
                guard let record = self.record(for: recordID) else {
                    // The object is gone locally; drop the change rather than resending forever.
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    return nil
                }
                return record
            }
        }
    }

    // MARK: - Failure Recovery

    private func handleFailedSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine
    ) {
        let recordID = failure.record.recordID
        guard let ckError = failure.error as? CKError else { return }

        switch ckError.code {
        case .serverRecordChanged:
            // Someone else wrote first. Take their record as the base so we keep the server's
            // change tag, re-apply our values on top, and try again.
            if let serverRecord = ckError.serverRecord {
                storeSystemFields(from: serverRecord)
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }

        case .zoneNotFound:
            // The zone was never created, or was deleted out from under us. Recreate it and
            // resend, otherwise this record can never land.
            let zone = CKRecordZone(zoneID: recordID.zoneID)
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .unknownItem:
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])

        default:
            print("Record save failed permanently: \(recordID) \(ckError)")
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn, .switchAccounts:
            // Everything local is unknown to the new account, so offer all of it.
            enqueueAllLocalData()
        case .signOut:
            // Leave local data alone: deleting someone's lists because they signed out of
            // iCloud would be a far worse bug than having them sit there unsynced.
            break
        @unknown default:
            break
        }
    }

    // MARK: - State Persistence

    private func stateURL(for scope: CKDatabase.Scope) -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let name = scope == .shared ? "sync-state-shared.json" : "sync-state-private.json"
        return support.appendingPathComponent(name)
    }

    private func loadStateSerialization(for scope: CKDatabase.Scope) -> CKSyncEngine.State.Serialization? {
        guard let url = stateURL(for: scope),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func save(_ serialization: CKSyncEngine.State.Serialization, for scope: CKDatabase.Scope) {
        guard let url = stateURL(for: scope) else { return }
        do {
            try JSONEncoder().encode(serialization).write(to: url, options: .atomic)
        } catch {
            print("Failed to persist sync state: \(error)")
        }
    }
}

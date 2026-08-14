//
//  CloudKitManager.swift
//  Tada
//

import Foundation
import CloudKit
import CoreData
import Combine

@Observable
@MainActor
final class CloudKitManager {
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)

        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.syncing, .syncing), (.success, .success):
                return true
            case (.error(let l), .error(let r)):
                return l == r
            default:
                return false
            }
        }

        var shouldShowIcon: Bool {
            switch self {
            case .syncing, .error:
                return true
            case .idle, .success:
                return false
            }
        }
    }

    var syncStatus: SyncStatus = .idle
    var lastSyncDate: Date?
    var accountStatus: CKAccountStatus = .couldNotDetermine

    private let container = CKContainer(identifier: "iCloud.net.kodare.Tada")
    private var cancellables = Set<AnyCancellable>()

    init() {
        Task {
            await checkAccountStatus()
        }
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCloudKitEvent(notification)
            }
            .store(in: &cancellables)
    }

    private nonisolated func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        Task { @MainActor in
            switch event.type {
            case .setup:
                // A failed setup is fatal for mirroring: no import/export events follow, so if
                // it isn't surfaced here the app looks like it is syncing fine forever.
                if let error = event.error {
                    syncStatus = .error(error.localizedDescription)
                }
            case .import, .export:
                if event.endDate == nil {
                    syncStatus = .syncing
                } else if let error = event.error {
                    if Self.isChangeTokenExpired(error) {
                        print("Change token expired — resetting local store for full re-sync")
                        PersistenceController.shared.resetCloudKitSync()
                        syncStatus = .syncing
                    } else {
                        syncStatus = .error(error.localizedDescription)
                    }
                } else {
                    syncStatus = .success
                    lastSyncDate = Date()
                    // Reset to idle after showing success
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if syncStatus == .success {
                            syncStatus = .idle
                        }
                    }
                }
            @unknown default:
                break
            }
        }
    }

    func checkAccountStatus() async {
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            print("Failed to get account status: \(error)")
        }
    }

    private static func isChangeTokenExpired(_ error: Error) -> Bool {
        let nsError = error as NSError
        // Direct CKError.changeTokenExpired
        if nsError.code == CKError.changeTokenExpired.rawValue {
            return true
        }
        // Wrapped in a partial failure
        if nsError.code == CKError.partialFailure.rawValue,
           let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            return partialErrors.values.contains { ($0 as NSError).code == CKError.changeTokenExpired.rawValue }
        }
        // CoreData wraps CKErrors in its own domain
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isChangeTokenExpired(underlying)
        }
        return false
    }

    func triggerSync() {
        // Force a save which will trigger CloudKit sync
        PersistenceController.shared.save()

        // Don't claim success we haven't seen: the real import/export events drive the status
        // from here. If mirroring is dead no events arrive at all, so only fall back to idle —
        // and never overwrite an error, which is the one thing worth showing.
        if syncStatus != .syncing {
            syncStatus = .syncing
        }

        Task {
            try? await Task.sleep(for: .seconds(10))
            if syncStatus == .syncing {
                syncStatus = .idle
            }
        }
    }
}

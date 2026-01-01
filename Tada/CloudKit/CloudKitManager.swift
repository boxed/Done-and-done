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
                break
            case .import, .export:
                if event.endDate == nil {
                    syncStatus = .syncing
                } else if let error = event.error {
                    syncStatus = .error(error.localizedDescription)
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

    func triggerSync() {
        // Force a save which will trigger CloudKit sync
        PersistenceController.shared.save()
        syncStatus = .syncing

        Task {
            try? await Task.sleep(for: .seconds(1))
            if syncStatus == .syncing {
                syncStatus = .success
                lastSyncDate = Date()
            }
            try? await Task.sleep(for: .seconds(2))
            if syncStatus == .success {
                syncStatus = .idle
            }
        }
    }
}

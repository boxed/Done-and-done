//
//  SyncStatusView.swift
//  Tada
//

import SwiftUI

struct SyncStatusView: View {
    var cloudKitManager: CloudKitManager

    var body: some View {
        Group {
            switch cloudKitManager.syncStatus {
            case .idle:
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
            case .syncing:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundStyle(.red)
            }
        }
        .animation(.default, value: cloudKitManager.syncStatus)
    }
}

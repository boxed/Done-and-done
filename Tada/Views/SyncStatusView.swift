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
            case .idle, .success:
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
            case .syncing:
                ProgressView()
                    .controlSize(.small)
            case .error:
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundStyle(.red)
            }
        }
        .animation(.default, value: cloudKitManager.syncStatus)
    }
}

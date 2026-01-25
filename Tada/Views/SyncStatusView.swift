//
//  SyncStatusView.swift
//  Tada
//

import SwiftUI

struct SyncStatusView: View {
    var cloudKitManager: CloudKitManager
    @State private var isPulsing = false
    @State private var showingErrorAlert = false

    var body: some View {
        Group {
            switch cloudKitManager.syncStatus {
            case .syncing:
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .opacity(isPulsing ? 0.3 : 0.8)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear {
                        isPulsing = true
                    }
                    .onDisappear {
                        isPulsing = false
                    }
            case .error(let errorMessage):
                Button {
                    showingErrorAlert = true
                } label: {
                    Image(systemName: "exclamationmark.icloud.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .alert("Sync Error", isPresented: $showingErrorAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(errorMessage)
                }
            case .idle, .success:
                EmptyView()
            }
        }
    }
}

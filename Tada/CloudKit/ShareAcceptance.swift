//
//  ShareAcceptance.swift
//  Tada
//
//  Opening a share link hands the app a CKShare.Metadata. Accepting it is what puts the shared
//  zone into our shared database — until then the shared sync engine has nothing to fetch.
//

import CloudKit
import SwiftUI

#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        // The share callback lives on the scene delegate; SwiftUI won't install one for us.
        configuration.delegateClass = ShareAcceptingSceneDelegate.self
        return configuration
    }
}

final class ShareAcceptingSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await CloudKitManager.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}
#endif

#if os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await CloudKitManager.shared.acceptShare(metadata: metadata)
        }
    }
}
#endif

//
//  TadaApp.swift
//  Tada
//

import SwiftUI
import CoreData

@main
struct TadaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let persistenceController = PersistenceController.shared

    @FocusedValue(\.selectedList) var selectedList
    @FocusedValue(\.selectedItem) var selectedItem

    init() {
        #if os(iOS)
        UIApplication.shared.applicationSupportsShakeToEdit = true
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                #if os(iOS)
                .onShake {
                    if persistenceController.container.viewContext.undoManager?.canUndo == true {
                        persistenceController.container.viewContext.undoManager?.undo()
                    }
                }
                #endif
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    persistenceController.container.viewContext.undoManager?.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!(persistenceController.container.viewContext.undoManager?.canUndo ?? false))

                Button("Redo") {
                    persistenceController.container.viewContext.undoManager?.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(persistenceController.container.viewContext.undoManager?.canRedo ?? false))
            }

            CommandGroup(replacing: .newItem) {
                Button("New List") {
                    NotificationCenter.default.post(name: .newList, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Item") {
                    NotificationCenter.default.post(name: .newItem, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            #if os(macOS)
            CommandGroup(after: .newItem) {
                Divider()
                Button("Synchronize Now") {
                    NotificationCenter.default.post(name: .syncNow, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            #endif

            CommandMenu("List") {
                Button("Mark Complete") {
                    if let item = selectedItem {
                        item.toggleCompletion()
                        try? persistenceController.container.viewContext.save()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(selectedItem == nil)

                Button("Toggle Star") {
                    if let item = selectedItem {
                        item.toggleStarred()
                        try? persistenceController.container.viewContext.save()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(selectedItem == nil)

                Divider()

                Button("Delete Item") {
                    if let item = selectedItem {
                        persistenceController.container.viewContext.delete(item)
                        try? persistenceController.container.viewContext.save()
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(selectedItem == nil)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                persistenceController.deleteOldCompletedItems()
            }
        }
    }
}

// MARK: - Notification Names for Keyboard Shortcuts

extension Notification.Name {
    static let newList = Notification.Name("newList")
    static let newItem = Notification.Name("newItem")
    static let syncNow = Notification.Name("syncNow")
    static let toggleComplete = Notification.Name("toggleComplete")
}

// MARK: - Shake Gesture Support

#if os(iOS)
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

struct ShakeDetector: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}

extension View {
    func onShake(_ action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(action: action))
    }
}
#endif

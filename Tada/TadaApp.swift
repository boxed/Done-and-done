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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
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
                        item.toggleStarted()
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
    static let toggleComplete = Notification.Name("toggleComplete")
}

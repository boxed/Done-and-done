//
//  TodoListView.swift
//  Tada
//

import SwiftUI
import CoreData
import CloudKit
import UniformTypeIdentifiers

struct TodoListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var list: TodoList
    var cloudKitManager: CloudKitManager

    @FetchRequest private var items: FetchedResults<TodoItem>

    @State private var newItemText = ""
    @FocusState private var isInputFocused: Bool
    @State private var currentShare: CKShare?
    @State private var showingShareSheet = false
    @State private var draggingItem: TodoItem?
    @State private var selectedItem: TodoItem?

    init(list: TodoList, cloudKitManager: CloudKitManager) {
        self.list = list
        self.cloudKitManager = cloudKitManager
        _items = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \TodoItem.order, ascending: true)],
            predicate: NSPredicate(format: "list == %@", list)
        )
    }

    private var hasCompletedItems: Bool {
        items.contains { $0.isCompleted && !$0.isHidden }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Active items section
                    ForEach(list.activeItems) { item in
                        TodoItemRow(item: item, isSelected: selectedItem == item) {
                            deleteItem(item)
                        } onSelect: {
                            selectedItem = item
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(itemBackground(for: item))
                        .draggable(item.objectID.uriRepresentation().absoluteString) {
                            Text(item.text ?? "")
                                .padding(8)
                                .background(.regularMaterial)
                                .cornerRadius(8)
                        }
                        .dropDestination(for: String.self) { items, location in
                            guard let uriString = items.first,
                                  let url = URL(string: uriString),
                                  let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                                  let droppedItem = try? viewContext.existingObject(with: objectID) as? TodoItem else {
                                return false
                            }
                            reorderItem(droppedItem, before: item)
                            return true
                        } isTargeted: { isTargeted in
                            // Visual feedback handled by background color
                        }
                        Divider()
                            .padding(.leading)
                    }

                    // Completed items section
                    if !list.completedItems.isEmpty {
                        HStack {
                            Text("Completed")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        ForEach(list.completedItems) { item in
                            TodoItemRow(item: item, isSelected: selectedItem == item) {
                                deleteItem(item)
                            } onSelect: {
                                selectedItem = item
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(itemBackground(for: item))
                            Divider()
                                .padding(.leading)
                        }
                    }
                }
            }

            // Quick entry field
            HStack {
                TextField("Add item...", text: $newItemText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit {
                        addItem()
                    }

                if !newItemText.isEmpty {
                    Button {
                        addItem()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(list.name ?? "Untitled")
        .toolbar {
            ToolbarItem {
                SyncStatusView(cloudKitManager: cloudKitManager)
                    .opacity(0.5)
            }

            ToolbarItem {
                Button {
                    cleanUp()
                } label: {
                    Label("Clean Up", systemImage: "wind")
                }
                .disabled(!hasCompletedItems)
            }

            ToolbarItem {
                ShareButton(list: list, currentShare: $currentShare, showingShareSheet: $showingShareSheet)
            }
        }
        .focusedSceneValue(\.selectedList, list)
        .focusedSceneValue(\.selectedItem, selectedItem)
        #if os(iOS)
        .toolbarRole(.editor)
        .sheet(isPresented: $showingShareSheet) {
            if let share = currentShare {
                CloudSharingSheet(share: share, list: list)
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .newItem)) { _ in
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cleanUp)) { _ in
            cleanUp()
        }
    }

    private func itemBackground(for item: TodoItem) -> Color {
        if draggingItem == item {
            return Color.accentColor.opacity(0.2)
        } else if selectedItem == item {
            return Color.accentColor.opacity(0.1)
        }
        return Color.clear
    }

    private func addItem() {
        guard !newItemText.isEmpty else { return }

        let maxOrder = list.activeItems.map(\.order).max() ?? -1
        let newItem = TodoItem.create(
            text: newItemText,
            order: maxOrder + 1,
            list: list,
            in: viewContext
        )
        try? viewContext.save()
        newItemText = ""
        selectedItem = newItem
    }

    private func deleteItem(_ item: TodoItem) {
        withAnimation {
            if selectedItem == item {
                selectedItem = nil
            }
            viewContext.delete(item)
            try? viewContext.save()
        }
    }

    private func reorderItem(_ movedItem: TodoItem, before targetItem: TodoItem) {
        var items = list.activeItems
        guard let movedIndex = items.firstIndex(of: movedItem),
              let targetIndex = items.firstIndex(of: targetItem),
              movedIndex != targetIndex else { return }

        withAnimation {
            items.remove(at: movedIndex)
            let insertIndex = movedIndex < targetIndex ? targetIndex - 1 : targetIndex
            items.insert(movedItem, at: insertIndex)

            for (index, item) in items.enumerated() {
                item.order = Int32(index)
            }
            try? viewContext.save()
        }
    }

    private func cleanUp() {
        withAnimation {
            for item in list.completedItems {
                item.isHidden = true
            }
            try? viewContext.save()
        }
        cloudKitManager.triggerSync()
    }
}

// MARK: - Share Button

struct ShareButton: View {
    let list: TodoList
    @Binding var currentShare: CKShare?
    @Binding var showingShareSheet: Bool

    var body: some View {
        #if os(macOS)
        Button {
            shareListMacOS()
        } label: {
            Label("Share", systemImage: list.isShared ? "person.2.fill" : "person.badge.plus")
        }
        #else
        Button {
            shareList()
        } label: {
            Label("Share", systemImage: list.isShared ? "person.2.fill" : "person.badge.plus")
        }
        #endif
    }

    #if os(macOS)
    private func shareListMacOS() {
        PersistenceController.shared.share(list) { share, error in
            if let error = error {
                print("Failed to share: \(error)")
                return
            }
            guard let share = share else { return }

            // Get the frontmost window
            guard let window = NSApp.keyWindow else { return }

            // Find the share button in the toolbar
            let toolbar = window.toolbar
            let shareItem = toolbar?.items.first { $0.label == "Share" }

            // Create sharing service picker
            let picker = NSSharingServicePicker(items: [share])

            // Show from toolbar item or window
            if let itemView = shareItem?.view {
                picker.show(relativeTo: itemView.bounds, of: itemView, preferredEdge: .minY)
            } else {
                // Fallback: show from top-right of content view
                if let contentView = window.contentView {
                    let rect = NSRect(x: contentView.bounds.maxX - 100, y: contentView.bounds.maxY - 50, width: 1, height: 1)
                    picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
                }
            }
        }
    }
    #endif

    private func shareList() {
        PersistenceController.shared.share(list) { share, error in
            if let error = error {
                print("Failed to share: \(error)")
                return
            }
            if let share = share {
                currentShare = share
                showingShareSheet = true
            }
        }
    }
}

// MARK: - CloudKit Sharing Sheet (iOS)

#if os(iOS)
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let list: TodoList

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: "iCloud.net.kodare.Tada"))
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(list: list)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let list: TodoList

        init(list: TodoList) {
            self.list = list
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            list.name
        }
    }
}
#endif

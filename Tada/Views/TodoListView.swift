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
    @State private var isInputFocused: Bool = false
    @State private var currentShare: CKShare?
    @State private var showingShareSheet = false
    @State private var selectedItem: TodoItem?

    init(list: TodoList, cloudKitManager: CloudKitManager) {
        self.list = list
        self.cloudKitManager = cloudKitManager
        _items = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \TodoItem.order, ascending: true)],
            predicate: NSPredicate(format: "list == %@", list)
        )
    }

    private var activeItems: [TodoItem] {
        items.filter { !$0.isCompleted }
    }

    private var completedItems: [TodoItem] {
        items.filter { $0.isCompleted }
            .sorted { ($0.completionTime ?? .distantPast) > ($1.completionTime ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                // Active items section
                ForEach(activeItems) { item in
                    TodoItemRow(
                        item: item,
                        isSelected: selectedItem == item
                    ) {
                        deleteItem(item)
                    } onSelect: {
                        selectedItem = item
                    }
                    .listRowBackground(itemBackground(for: item))
                }
                .onMove(perform: moveItems)

                // Completed items section
                if !completedItems.isEmpty {
                    Section {
                        ForEach(completedItems) { item in
                            TodoItemRow(item: item, isSelected: selectedItem == item) {
                                deleteItem(item)
                            } onSelect: {
                                selectedItem = item
                            }
                            .listRowBackground(itemBackground(for: item))
                        }
                    } header: {
                        Text("Completed")
                    }
                }
            }
            .listStyle(.plain)
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif

            // Quick entry field
            HStack {
                QuickEntryTextField(
                    placeholder: "Add item...",
                    text: $newItemText,
                    isFocused: $isInputFocused,
                    onSubmit: {
                        if newItemText.isEmpty {
                            return false  // Dismiss keyboard
                        } else {
                            addItem()
                            return true   // Keep keyboard open
                        }
                    }
                )

                Button {
                    addItem()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .opacity(newItemText.isEmpty ? 0 : 1)
                .disabled(newItemText.isEmpty)
            }
            .frame(height: 22)
            .padding()
            .background(.bar)
        }
        .navigationTitle(list.name ?? "Untitled")
        .toolbar {
            ToolbarItem {
                SyncStatusView(cloudKitManager: cloudKitManager)
            }

            ToolbarItem {
                ShareButton(list: list, currentShare: $currentShare, showingShareSheet: $showingShareSheet)
            }
        }
        .focusedSceneValue(\.selectedList, list)
        .focusedSceneValue(\.selectedItem, selectedItem)
        #if os(iOS)
        .sheet(isPresented: $showingShareSheet) {
            if let share = currentShare {
                CloudSharingSheet(share: share, list: list)
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .newItem)) { _ in
            isInputFocused = true
        }
    }

    private func itemBackground(for item: TodoItem) -> Color {
        if selectedItem == item {
            return Color.accentColor.opacity(0.1)
        }
        return Color.clear
    }

    private func addItem() {
        guard !newItemText.isEmpty else { return }

        let maxOrder = activeItems.map(\.order).max() ?? -1
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

    private func moveItems(from source: IndexSet, to destination: Int) {
        var reorderedItems = activeItems
        reorderedItems.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reorderedItems.enumerated() {
            item.order = Int32(index)
        }
        try? viewContext.save()
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

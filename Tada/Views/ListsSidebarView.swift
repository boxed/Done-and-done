//
//  ListsSidebarView.swift
//  Tada
//

import SwiftUI
import CoreData

struct ListsSidebarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \TodoList.order, ascending: true)],
        animation: .default
    )
    private var lists: FetchedResults<TodoList>

    @Binding var selectedList: TodoList?

    @State private var showingNewListDialog = false
    @State private var newListName = ""
    @State private var editingList: TodoList?
    @State private var editingName = ""
    @State private var listToDelete: TodoList?
    @State private var showingDeleteConfirmation = false
    @State private var hasAppeared = false
    @State private var listToDuplicate: TodoList?
    @State private var showingDuplicateDialog = false
    @State private var duplicateListName = ""

    @AppStorage("lastSelectedListID") private var lastSelectedListID: String = ""

    var body: some View {
        List(selection: $selectedList) {
            ForEach(lists) { list in
                NavigationLink(value: list) {
                    if editingList == list {
                        TextField("List name", text: $editingName)
                            .onSubmit {
                                saveListName()
                            }
                            #if os(macOS)
                            .onExitCommand {
                                cancelEditing()
                            }
                            #endif
                    } else {
                        HStack {
                            Text(list.name ?? "Untitled")
                            Spacer()
                            if list.isShared {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Text("\(list.activeItems.count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
                .contextMenu {
                    Button {
                        startEditing(list)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        listToDuplicate = list
                        duplicateListName = "\(list.name ?? "List") Copy"
                        showingDuplicateDialog = true
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }

                    Divider()

                    Button(role: .destructive) {
                        listToDelete = list
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: moveLists)
            .onDelete(perform: confirmDeleteLists)
        }
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem {
                Button {
                    newListName = ""
                    showingNewListDialog = true
                } label: {
                    Label("Add List", systemImage: "plus")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
        .alert("New List", isPresented: $showingNewListDialog) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) {
                newListName = ""
            }
            Button("Create") {
                addList()
            }
            .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for your new list.")
        }
        .confirmationDialog(
            "Delete List",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let list = listToDelete {
                    deleteList(list)
                }
                listToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                listToDelete = nil
            }
        } message: {
            if let list = listToDelete {
                Text("Are you sure you want to delete \"\(list.name ?? "this list")\"? This will also delete all \(list.itemsArray.count) items in the list.")
            }
        }
        .alert("Duplicate List", isPresented: $showingDuplicateDialog) {
            TextField("List name", text: $duplicateListName)
            Button("Cancel", role: .cancel) {
                duplicateListName = ""
                listToDuplicate = nil
            }
            Button("Duplicate") {
                duplicateList()
            }
            .disabled(duplicateListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the copied list.")
        }
        .onAppear {
            if lists.isEmpty {
                createDefaultList()
            }
            // Only auto-select on first appearance, not when navigating back
            if !hasAppeared {
                hasAppeared = true
                if selectedList == nil && !lastSelectedListID.isEmpty {
                    // Restore last selected list if we have one saved
                    if let lastID = UUID(uuidString: lastSelectedListID),
                       let lastList = lists.first(where: { $0.id == lastID }) {
                        selectedList = lastList
                    }
                }
            }
        }
        .onChange(of: selectedList) { oldValue, newValue in
            if let list = newValue, let id = list.id {
                lastSelectedListID = id.uuidString
            } else {
                // User exited to sidebar, clear the saved list
                lastSelectedListID = ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newList)) { _ in
            newListName = ""
            showingNewListDialog = true
        }
    }

    private func startEditing(_ list: TodoList) {
        editingList = list
        editingName = list.name ?? ""
    }

    private func saveListName() {
        guard let list = editingList, !editingName.isEmpty else {
            cancelEditing()
            return
        }

        list.name = editingName
        try? viewContext.save()
        editingList = nil
        editingName = ""
    }

    private func cancelEditing() {
        editingList = nil
        editingName = ""
    }

    private func addList() {
        let trimmedName = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            newListName = ""
            return
        }

        withAnimation {
            let newList = TodoList.create(
                name: trimmedName,
                order: Int32(lists.count),
                in: viewContext
            )
            try? viewContext.save()
            newListName = ""
            selectedList = newList
        }
    }

    private func createDefaultList() {
        let defaultList = TodoList.create(name: "My List", order: 0, in: viewContext)
        try? viewContext.save()
        selectedList = defaultList
    }

    private func deleteList(_ list: TodoList) {
        withAnimation {
            if selectedList == list {
                selectedList = lists.first { $0 != list }
            }
            viewContext.delete(list)
            try? viewContext.save()
        }
    }

    private func confirmDeleteLists(offsets: IndexSet) {
        if let index = offsets.first {
            listToDelete = lists[index]
            showingDeleteConfirmation = true
        }
    }

    private func moveLists(from source: IndexSet, to destination: Int) {
        var reorderedLists = Array(lists)
        reorderedLists.move(fromOffsets: source, toOffset: destination)
        for (index, list) in reorderedLists.enumerated() {
            list.order = Int32(index)
        }
        try? viewContext.save()
    }

    private func duplicateList() {
        guard let sourceList = listToDuplicate else { return }
        let trimmedName = duplicateListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        withAnimation {
            let newList = TodoList.create(
                name: trimmedName,
                order: Int32(lists.count),
                in: viewContext
            )

            // Copy all non-hidden items
            for sourceItem in sourceList.itemsArray where !sourceItem.isHidden {
                let newItem = TodoItem(context: viewContext)
                newItem.id = UUID()
                newItem.text = sourceItem.text
                newItem.creationTime = Date()
                newItem.order = sourceItem.order
                newItem.isHidden = false
                newItem.completionTime = sourceItem.completionTime
                newItem.startedTime = sourceItem.startedTime
                newItem.list = newList
            }

            try? viewContext.save()
            selectedList = newList
        }

        duplicateListName = ""
        listToDuplicate = nil
    }
}

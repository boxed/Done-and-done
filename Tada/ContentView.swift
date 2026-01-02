//
//  ContentView.swift
//  Tada
//

import SwiftUI
import CoreData

struct ContentView: View {
    @State private var selectedList: TodoList?
    @State private var cloudKitManager = CloudKitManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ListsSidebarView(selectedList: $selectedList)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                #endif
        } detail: {
            if let list = selectedList {
                TodoListView(list: list, cloudKitManager: cloudKitManager)
                    .id(list.objectID)
            } else {
                ContentUnavailableView(
                    "No List Selected",
                    systemImage: "checklist",
                    description: Text("Select a list from the sidebar or create a new one.")
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

//
//  ContentView.swift
//  Tada

import SwiftUI
import CoreData

struct ContentView: View {
    @State private var selectedList: TodoList?
    @State private var cloudKitManager = CloudKitManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    init(){
        #if !os(macOS)
        UINavigationBar.setAnimationsEnabled(false)
        #endif
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ListsSidebarView(selectedList: $selectedList, cloudKitManager: cloudKitManager)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView
        }
        #else
        iOSNavigationView
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
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

    #if !os(macOS)
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar

    private var iOSNavigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredColumn) {
            ListsSidebarView(selectedList: $selectedList, cloudKitManager: cloudKitManager)
        } detail: {
            detailView
        }
        .onChange(of: selectedList) { _, newValue in
            preferredColumn = newValue != nil ? .detail : .sidebar
        }
        .onChange(of: preferredColumn) { _, newValue in
            if newValue == .sidebar {
                selectedList = nil
            }
        }
    }
    #endif
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

//
//  ContentView.swift
//  Tada

import SwiftUI
import CoreData

struct ContentView: View {
    @State private var selectedList: TodoList?
    @State private var cloudKitManager = CloudKitManager.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path: [TodoList] = []

    @ViewBuilder
    private var iOSNavigationView: some View {
        if horizontalSizeClass == .compact {
            // On iPhone this is a plain navigation stack rather than a compact
            // NavigationSplitView. A tap on a row pushes because the link appends to `path`, and
            // a pop always removes it again. The split view instead navigated by *changing the
            // selection*, and relied on SwiftUI writing `preferredCompactColumn` back to us on
            // pop. When that write-back didn't happen, `selectedList` stayed pointing at the list
            // we had just left, so tapping that same row changed nothing and no push happened —
            // navigation looked dead until the app was force quit.
            NavigationStack(path: $path) {
                ListsSidebarView(selectedList: $selectedList, cloudKitManager: cloudKitManager)
                    .navigationDestination(for: TodoList.self) { list in
                        TodoListView(list: list, cloudKitManager: cloudKitManager)
                            .id(list.objectID)
                    }
            }
            .onChange(of: path) { _, newValue in
                if selectedList != newValue.last {
                    selectedList = newValue.last
                }
            }
            .onChange(of: selectedList) { _, newValue in
                // Selecting a list in code (creating or duplicating one) still opens it.
                if let list = newValue {
                    if path.last != list {
                        path = [list]
                    }
                } else if !path.isEmpty {
                    path = []
                }
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                ListsSidebarView(selectedList: $selectedList, cloudKitManager: cloudKitManager)
            } detail: {
                detailView
            }
        }
    }
    #endif
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

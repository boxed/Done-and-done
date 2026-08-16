//
//  TodoList+Extensions.swift
//  Tada
//

import Foundation
import CoreData

extension TodoList {
    var itemsArray: [TodoItem] {
        let set = items as? Set<TodoItem> ?? []
        return Array(set)
    }

    var activeItems: [TodoItem] {
        itemsArray
            .filter { !$0.isCompleted && !$0.isHidden }
            .sorted { $0.order < $1.order }
    }

    var completedItems: [TodoItem] {
        itemsArray
            .filter { $0.isCompleted && !$0.isHidden }
            .sorted { ($0.completionTime ?? .distantPast) > ($1.completionTime ?? .distantPast) }
    }

    var visibleItems: [TodoItem] {
        activeItems + completedItems
    }

    static func create(name: String, order: Int32, in context: NSManagedObjectContext) -> TodoList {
        let list = TodoList(context: context)
        let id = UUID()
        list.id = id
        list.name = name
        list.creationDate = Date()
        list.order = order
        // Each list syncs in its own record zone so it can be shared on its own; the zone is
        // named after the list from the moment it exists.
        list.zoneName = CloudKitManager.zoneName(forListID: id)
        return list
    }
}

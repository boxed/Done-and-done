//
//  TodoItem+Extensions.swift
//  Tada
//

import Foundation
import CoreData

extension TodoItem {
    var isCompleted: Bool {
        completionTime != nil
    }

    var isStarred: Bool {
        startedTime != nil
    }

    func toggleCompletion() {
        if isCompleted {
            completionTime = nil
        } else {
            completionTime = Date()
        }
    }

    func toggleStarred() {
        if isStarred {
            startedTime = nil
        } else {
            startedTime = Date()
        }
    }

    static func create(text: String, order: Int32, list: TodoList, in context: NSManagedObjectContext) -> TodoItem {
        let item = TodoItem(context: context)
        item.id = UUID()
        item.text = text
        item.creationTime = Date()
        item.order = order
        item.isHidden = false
        item.list = list
        return item
    }
}

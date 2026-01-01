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
            moveToTop()
        }
    }

    private func moveToTop() {
        guard let list = list else { return }
        let activeItems = list.activeItems.filter { $0 != self }

        // Set this item to order 0
        self.order = 0

        // Shift all other active items down
        for (index, item) in activeItems.enumerated() {
            item.order = Int32(index + 1)
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

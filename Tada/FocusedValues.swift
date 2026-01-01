//
//  FocusedValues.swift
//  Tada
//

import SwiftUI

// MARK: - Focused Values for Keyboard Shortcuts

struct FocusedListKey: FocusedValueKey {
    typealias Value = TodoList
}

struct FocusedItemKey: FocusedValueKey {
    typealias Value = TodoItem
}

extension FocusedValues {
    var selectedList: TodoList? {
        get { self[FocusedListKey.self] }
        set { self[FocusedListKey.self] = newValue }
    }

    var selectedItem: TodoItem? {
        get { self[FocusedItemKey.self] }
        set { self[FocusedItemKey.self] = newValue }
    }
}

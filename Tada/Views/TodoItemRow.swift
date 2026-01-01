//
//  TodoItemRow.swift
//  Tada
//

import SwiftUI
import CoreData

struct TodoItemRow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: TodoItem
    var isSelected: Bool = false
    var onDelete: () -> Void
    var onSelect: (() -> Void)? = nil

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation {
                    item.toggleCompletion()
                    try? viewContext.save()
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("Item text", text: $editText)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        saveEdit()
                    }
                    #if os(macOS)
                    .onExitCommand {
                        cancelEdit()
                    }
                    #endif
                    .onChange(of: isTextFieldFocused) { oldValue, newValue in
                        if !newValue {
                            saveEdit()
                        }
                    }
            } else {
                Text(item.text ?? "")
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        startEditing()
                    }
                    .onTapGesture(count: 1) {
                        onSelect?()
                    }
            }

            Spacer(minLength: 0)

            if item.isStarted {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation {
                    item.toggleStarted()
                    try? viewContext.save()
                }
            } label: {
                Label(
                    item.isStarted ? "Stop" : "Start",
                    systemImage: item.isStarted ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button {
                startEditing()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                withAnimation {
                    item.toggleStarted()
                    try? viewContext.save()
                }
            } label: {
                Label(
                    item.isStarted ? "Stop Working" : "Start Working",
                    systemImage: item.isStarted ? "star.slash" : "star"
                )
            }

            Button {
                withAnimation {
                    item.toggleCompletion()
                    try? viewContext.save()
                }
            } label: {
                Label(
                    item.isCompleted ? "Mark Incomplete" : "Mark Complete",
                    systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                )
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func startEditing() {
        editText = item.text ?? ""
        isEditing = true
        isTextFieldFocused = true
    }

    private func saveEdit() {
        if !editText.isEmpty {
            item.text = editText
            try? viewContext.save()
        }
        isEditing = false
        editText = ""
    }

    private func cancelEdit() {
        isEditing = false
        editText = ""
    }
}

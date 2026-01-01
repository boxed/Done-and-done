# Tada

Tada is a todo app focused on simplicity, clarity, and performance.

Features:

- Each user has a list of todo lists
- Each item in the a todo list has these properties:
    - stared time
    - completion time
    - creation time
    - order (users can manually reorder with drag-and-drop)
- By default, completed items become hidden, when the phone is locked or the user switches to another program, or when pressing the "clean up" button (which has an icon like the weather symbol for wind)
- Completed icons are shown below non-completed icons. Completed icons are sorted by completion time, newest at the top.
- When adding items, you can add multiple items easily because every time you press enter the item is created and the input field is cleared so you can add another item
- Users can share lists (via CloudKit Shared Records https://developer.apple.com/documentation/cloudkit/shared-records)
- When doing synchronization with CloudKit, this will always be clearly visible to the user so the user knows that it's happening and when it's done


The backend is all handled by iCloud/CloudKit
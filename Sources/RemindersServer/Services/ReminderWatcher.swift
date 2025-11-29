import Vapor
import EventKit
import Fluent

/// Watches for changes in macOS Reminders via EKEventStoreChanged notification
final class ReminderWatcher: @unchecked Sendable {
    private let app: Application
    private let store: EKEventStore
    private var observer: NSObjectProtocol?
    
    init(app: Application) {
        self.app = app
        self.store = EKEventStore()
    }
    
    /// Starts watching for reminder changes
    func start() async throws {
        // Request access to reminders
        let granted = try await store.requestAccess(to: .reminder)
        
        guard granted else {
            app.logger.error("Reminders access denied")
            throw Abort(.forbidden, reason: "Reminders access denied")
        }
        
        app.logger.info("Reminders access granted, starting watcher")
        
        // Perform initial sync
        try await performSync()
        
        // Subscribe to changes
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task {
                do {
                    try await self.handleChange()
                } catch {
                    self.app.logger.report(error: error)
                }
            }
        }
        
        app.logger.info("ReminderWatcher started - listening for EKEventStoreChanged")
    }
    
    /// Stops watching for changes
    func stop() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
            app.logger.info("ReminderWatcher stopped")
        }
    }
    
    /// Handles a change notification from EventKit
    private func handleChange() async throws {
        app.logger.info("EKEventStoreChanged received - syncing reminders")
        try await performSync()
    }
    
    /// Syncs reminders from EventKit, detects changes, and dispatches webhooks
    private func performSync() async throws {
        let db = app.db
        
        // Fetch current reminders from EventKit
        let currentReminders = try await fetchReminders()
        
        // Load existing snapshots
        let snapshots = try await ReminderSnapshot.query(on: db).all()
        let snapshotMap = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id!, $0) })
        
        var changes: [ReminderChange] = []
        var seenIDs: Set<String> = []
        
        // Check for new and updated reminders
        for reminder in currentReminders {
            let reminderID = reminder.calendarItemIdentifier
            seenIDs.insert(reminderID)
            
            let title = reminder.title ?? ""
            let listName = reminder.calendar?.title ?? ""
            let isCompleted = reminder.isCompleted
            let dueDate = reminder.dueDateComponents?.date
            
            if let existing = snapshotMap[reminderID] {
                // Check if changed
                let newChecksum = ReminderSnapshot.computeChecksum(
                    title: title,
                    listName: listName,
                    isCompleted: isCompleted,
                    dueDate: dueDate
                )
                
                if existing.checksum != newChecksum {
                    // Determine change type
                    let eventType: ReminderChange.EventType
                    if !existing.isCompleted && isCompleted {
                        eventType = .completed
                    } else {
                        eventType = .updated
                    }
                    
                    let oldSnapshot = ReminderSnapshotData(
                        reminderID: reminderID,
                        title: existing.title,
                        listName: existing.listName,
                        isCompleted: existing.isCompleted,
                        dueDate: existing.dueDate
                    )
                    
                    let newSnapshot = ReminderSnapshotData(
                        reminderID: reminderID,
                        title: title,
                        listName: listName,
                        isCompleted: isCompleted,
                        dueDate: dueDate
                    )
                    
                    changes.append(ReminderChange(
                        eventType: eventType,
                        reminder: newSnapshot,
                        previousState: oldSnapshot
                    ))
                    
                    // Update snapshot
                    existing.title = title
                    existing.listName = listName
                    existing.isCompleted = isCompleted
                    existing.dueDate = dueDate
                    existing.updateChecksum()
                    try await existing.save(on: db)
                }
            } else {
                // New reminder
                let snapshot = ReminderSnapshot(
                    reminderID: reminderID,
                    title: title,
                    listName: listName,
                    isCompleted: isCompleted,
                    dueDate: dueDate
                )
                try await snapshot.create(on: db)
                
                let snapshotData = ReminderSnapshotData(
                    reminderID: reminderID,
                    title: title,
                    listName: listName,
                    isCompleted: isCompleted,
                    dueDate: dueDate
                )
                
                changes.append(ReminderChange(
                    eventType: .created,
                    reminder: snapshotData,
                    previousState: nil
                ))
            }
        }
        
        // Check for deleted reminders
        for snapshot in snapshots {
            if !seenIDs.contains(snapshot.id!) {
                let snapshotData = ReminderSnapshotData(
                    reminderID: snapshot.id!,
                    title: snapshot.title,
                    listName: snapshot.listName,
                    isCompleted: snapshot.isCompleted,
                    dueDate: snapshot.dueDate
                )
                
                changes.append(ReminderChange(
                    eventType: .deleted,
                    reminder: snapshotData,
                    previousState: snapshotData
                ))
                
                try await snapshot.delete(on: db)
            }
        }
        
        // Dispatch webhooks for changes
        if !changes.isEmpty {
            app.logger.info("Detected \(changes.count) reminder change(s)")
            try await WebhookService.dispatch(changes: changes, app: app)
        }
    }
    
    /// Fetches all reminders from EventKit
    private func fetchReminders() async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = store.predicateForReminders(in: nil)
            store.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

// MARK: - Data Structures

struct ReminderSnapshotData: Content {
    let reminderID: String
    let title: String
    let listName: String
    let isCompleted: Bool
    let dueDate: Date?
}

struct ReminderChange {
    enum EventType: String, Codable {
        case created
        case updated
        case completed
        case deleted
    }
    
    let eventType: EventType
    let reminder: ReminderSnapshotData
    let previousState: ReminderSnapshotData?
}

// MARK: - Application Extension

extension Application {
    private struct ReminderWatcherKey: StorageKey {
        typealias Value = ReminderWatcher
    }
    
    var reminderWatcher: ReminderWatcher? {
        get { storage[ReminderWatcherKey.self] }
        set { storage[ReminderWatcherKey.self] = newValue }
    }
}

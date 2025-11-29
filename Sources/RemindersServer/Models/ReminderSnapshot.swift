import Fluent
import Vapor

final class ReminderSnapshot: Model, Content, @unchecked Sendable {
    static let schema = "reminder_snapshots"
    
    @ID(custom: "reminder_id", generatedBy: .user)
    var id: String?
    
    @Field(key: "title")
    var title: String
    
    @Field(key: "list_name")
    var listName: String
    
    @Field(key: "is_completed")
    var isCompleted: Bool
    
    @Field(key: "due_date")
    var dueDate: Date?
    
    @Field(key: "checksum")
    var checksum: String
    
    @Timestamp(key: "last_seen", on: .update)
    var lastSeen: Date?
    
    init() { }
    
    init(
        reminderID: String,
        title: String,
        listName: String,
        isCompleted: Bool,
        dueDate: Date? = nil
    ) {
        self.id = reminderID
        self.title = title
        self.listName = listName
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.checksum = Self.computeChecksum(
            title: title,
            listName: listName,
            isCompleted: isCompleted,
            dueDate: dueDate
        )
    }
    
    static func computeChecksum(
        title: String,
        listName: String,
        isCompleted: Bool,
        dueDate: Date?
    ) -> String {
        let dateString = dueDate?.timeIntervalSince1970.description ?? "nil"
        let combined = "\(title)|\(listName)|\(isCompleted)|\(dateString)"
        
        // Simple hash - in production you might use CryptoKit
        var hash = 0
        for char in combined.unicodeScalars {
            hash = 31 &* hash &+ Int(char.value)
        }
        return String(format: "%08x", abs(hash))
    }
    
    func updateChecksum() {
        self.checksum = Self.computeChecksum(
            title: title,
            listName: listName,
            isCompleted: isCompleted,
            dueDate: dueDate
        )
    }
}

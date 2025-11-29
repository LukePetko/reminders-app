import Fluent

struct CreateReminderSnapshot: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("reminder_snapshots")
            .field("reminder_id", .string, .identifier(auto: false))
            .field("title", .string, .required)
            .field("list_name", .string, .required)
            .field("is_completed", .bool, .required)
            .field("due_date", .datetime)
            .field("checksum", .string, .required)
            .field("last_seen", .datetime)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("reminder_snapshots").delete()
    }
}

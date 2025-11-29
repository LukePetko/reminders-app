import Fluent

struct CreateWebhook: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("webhooks")
            .id()
            .field("url", .string, .required)
            .field("secret", .string)
            .field("reminder_id", .string)
            .field("list_name", .string)
            .field("events", .array(of: .string), .required)
            .field("active", .bool, .required, .custom("DEFAULT TRUE"))
            .field("created_at", .datetime)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("webhooks").delete()
    }
}

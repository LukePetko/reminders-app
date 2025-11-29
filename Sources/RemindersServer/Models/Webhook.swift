import Fluent
import Vapor

final class Webhook: Model, Content, @unchecked Sendable {
    static let schema = "webhooks"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "url")
    var url: String
    
    @Field(key: "secret")
    var secret: String?
    
    @Field(key: "reminder_id")
    var reminderID: String?
    
    @Field(key: "list_name")
    var listName: String?
    
    @Field(key: "events")
    var events: [String]
    
    @Field(key: "active")
    var active: Bool
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() { }
    
    init(
        id: UUID? = nil,
        url: String,
        secret: String? = nil,
        reminderID: String? = nil,
        listName: String? = nil,
        events: [String] = ["created", "updated", "completed", "deleted"],
        active: Bool = true
    ) {
        self.id = id
        self.url = url
        self.secret = secret
        self.reminderID = reminderID
        self.listName = listName
        self.events = events
        self.active = active
    }
}

// MARK: - DTOs

struct CreateWebhookDTO: Content {
    let url: String
    let secret: String?
    let reminderID: String?
    let listName: String?
    let events: [String]?
}

struct WebhookResponseDTO: Content {
    let id: UUID
    let url: String
    let reminderID: String?
    let listName: String?
    let events: [String]
    let active: Bool
    let createdAt: Date?
    
    init(from webhook: Webhook) {
        self.id = webhook.id!
        self.url = webhook.url
        self.reminderID = webhook.reminderID
        self.listName = webhook.listName
        self.events = webhook.events
        self.active = webhook.active
        self.createdAt = webhook.createdAt
    }
}

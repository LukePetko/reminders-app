import Vapor
import Fluent
import EventKit

struct ReminderDTO: Content {
    let id: String
    let title: String
    let listName: String
}


func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    app.get("date") { req async -> String in
        let date = Date()
        return "The current date is \(date)"
    }
    
    app.post("test") { req async throws -> Test in
        let test = Test(name: "test" + String(Int.random(in: 0..<6)))
        try await test.create(on: req.db)
        return test
    }
    
    app.get("test") { req async throws in
        try await Test.query(on: req.db).all()
    }

    app.get("reminders") { req -> [ReminderDTO] in
        let store = EKEventStore()
        var titles: [ReminderDTO] = []
        let sema = DispatchSemaphore(value: 0)

        store.requestAccess(to: .reminder) { granted, error in
            guard granted, error == nil else {
                sema.signal()
                return
            }

            let predicate = store.predicateForReminders(in: nil)
            store.fetchReminders(matching: predicate) { reminders in
                if let reminders = reminders {
                    titles = reminders
                        .filter { $0.isCompleted == false }
                        .map { 
                            ReminderDTO(
                                id: $0.calendarItemIdentifier,
                                title: $0.title ?? "",
                                listName: $0.calendar?.title ?? ""
                            )
                        }
                }
                sema.signal()
            }
        }

        sema.wait()
        return titles
    }
    
    // MARK: - Webhook Routes
    
    // List all webhooks
    app.get("webhooks") { req async throws -> [WebhookResponseDTO] in
        let webhooks = try await Webhook.query(on: req.db).all()
        return webhooks.map { WebhookResponseDTO(from: $0) }
    }
    
    // Create a new webhook
    app.post("webhooks") { req async throws -> WebhookResponseDTO in
        let dto = try req.content.decode(CreateWebhookDTO.self)
        
        // Validate URL
        guard URL(string: dto.url) != nil else {
            throw Abort(.badRequest, reason: "Invalid URL")
        }
        
        let webhook = Webhook(
            url: dto.url,
            secret: dto.secret,
            reminderID: dto.reminderID,
            listName: dto.listName,
            events: dto.events ?? ["created", "updated", "completed", "deleted"],
            active: true
        )
        
        try await webhook.create(on: req.db)
        return WebhookResponseDTO(from: webhook)
    }
    
    // Get a specific webhook
    app.get("webhooks", ":id") { req async throws -> WebhookResponseDTO in
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid webhook ID")
        }
        
        guard let webhook = try await Webhook.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Webhook not found")
        }
        
        return WebhookResponseDTO(from: webhook)
    }
    
    // Delete a webhook
    app.delete("webhooks", ":id") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid webhook ID")
        }
        
        guard let webhook = try await Webhook.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Webhook not found")
        }
        
        try await webhook.delete(on: req.db)
        return .noContent
    }
    
    // Test a webhook
    app.post("webhooks", ":id", "test") { req async throws -> [String: Bool] in
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid webhook ID")
        }
        
        guard let webhook = try await Webhook.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Webhook not found")
        }
        
        let success = try await WebhookService.sendTest(webhook: webhook, app: req.application)
        return ["success": success]
    }
    
    // Toggle webhook active status
    app.patch("webhooks", ":id", "toggle") { req async throws -> WebhookResponseDTO in
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid webhook ID")
        }
        
        guard let webhook = try await Webhook.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Webhook not found")
        }
        
        webhook.active.toggle()
        try await webhook.save(on: req.db)
        
        return WebhookResponseDTO(from: webhook)
    }
}

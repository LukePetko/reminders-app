import Vapor
import Fluent
import EventKit

struct ReminderDTO: Content {
    let id: String
    let title: String
    let listName: String
    let isCompleted: Bool?
    let dueDate: Date?
    let notes: String?
}

struct CreateReminderDTO: Content {
    let title: String
    let listName: String?
    let notes: String?
    let dueDate: Date?
}


func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
    }
    
    // Swagger UI
    app.get("docs") { req -> Response in
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Reminders API Documentation</title>
            <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
        </head>
        <body>
            <div id="swagger-ui"></div>
            <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
            <script>
                SwaggerUIBundle({
                    url: "/swagger.json",
                    dom_id: '#swagger-ui',
                    presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
                    layout: "BaseLayout"
                });
            </script>
        </body>
        </html>
        """
        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html"],
            body: .init(string: html)
        )
    }
    
    // OpenAPI spec (embedded)
    app.get("swagger.json") { req -> Response in
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(string: swaggerJSON)
        )
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

    // Get all incomplete reminders
    app.get("reminders") { req async throws -> [ReminderDTO] in
        let store = EKEventStore()
        let granted = try await store.requestAccess(to: .reminder)
        
        guard granted else {
            throw Abort(.forbidden, reason: "Reminders access denied")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = store.predicateForReminders(in: nil)
            store.fetchReminders(matching: predicate) { reminders in
                let dtos = (reminders ?? [])
                    .filter { !$0.isCompleted }
                    .map { reminder in
                        ReminderDTO(
                            id: reminder.calendarItemIdentifier,
                            title: reminder.title ?? "",
                            listName: reminder.calendar?.title ?? "",
                            isCompleted: reminder.isCompleted,
                            dueDate: reminder.dueDateComponents?.date,
                            notes: reminder.notes
                        )
                    }
                continuation.resume(returning: dtos)
            }
        }
    }
    
    // Create a new reminder
    app.post("reminders") { req async throws -> ReminderDTO in
        let dto = try req.content.decode(CreateReminderDTO.self)
        
        let store = EKEventStore()
        let granted = try await store.requestAccess(to: .reminder)
        
        guard granted else {
            throw Abort(.forbidden, reason: "Reminders access denied")
        }
        
        // Find the calendar (list) to add the reminder to
        let calendars = store.calendars(for: .reminder)
        let calendar: EKCalendar
        
        if let listName = dto.listName,
           let found = calendars.first(where: { $0.title == listName }) {
            calendar = found
        } else if let defaultCalendar = store.defaultCalendarForNewReminders() {
            calendar = defaultCalendar
        } else if let firstCalendar = calendars.first {
            calendar = firstCalendar
        } else {
            throw Abort(.badRequest, reason: "No reminder lists available")
        }
        
        // Create the reminder
        let reminder = EKReminder(eventStore: store)
        reminder.title = dto.title
        reminder.calendar = calendar
        reminder.notes = dto.notes
        
        if let dueDate = dto.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        
        try store.save(reminder, commit: true)
        
        return ReminderDTO(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            listName: reminder.calendar?.title ?? "",
            isCompleted: reminder.isCompleted,
            dueDate: reminder.dueDateComponents?.date,
            notes: reminder.notes
        )
    }
    
    // Get a specific reminder
    app.get("reminders", ":id") { req async throws -> ReminderDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Invalid reminder ID")
        }
        
        let store = EKEventStore()
        let granted = try await store.requestAccess(to: .reminder)
        
        guard granted else {
            throw Abort(.forbidden, reason: "Reminders access denied")
        }
        
        guard let item = store.calendarItem(withIdentifier: id),
              let reminder = item as? EKReminder else {
            throw Abort(.notFound, reason: "Reminder not found")
        }
        
        return ReminderDTO(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            listName: reminder.calendar?.title ?? "",
            isCompleted: reminder.isCompleted,
            dueDate: reminder.dueDateComponents?.date,
            notes: reminder.notes
        )
    }
    
    // Complete a reminder
    app.post("reminders", ":id", "complete") { req async throws -> ReminderDTO in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Invalid reminder ID")
        }
        
        let store = EKEventStore()
        let granted = try await store.requestAccess(to: .reminder)
        
        guard granted else {
            throw Abort(.forbidden, reason: "Reminders access denied")
        }
        
        guard let item = store.calendarItem(withIdentifier: id),
              let reminder = item as? EKReminder else {
            throw Abort(.notFound, reason: "Reminder not found")
        }
        
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        
        return ReminderDTO(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            listName: reminder.calendar?.title ?? "",
            isCompleted: reminder.isCompleted,
            dueDate: reminder.dueDateComponents?.date,
            notes: reminder.notes
        )
    }
    
    // Delete a reminder
    app.delete("reminders", ":id") { req async throws -> HTTPStatus in
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Invalid reminder ID")
        }
        
        let store = EKEventStore()
        let granted = try await store.requestAccess(to: .reminder)
        
        guard granted else {
            throw Abort(.forbidden, reason: "Reminders access denied")
        }
        
        guard let item = store.calendarItem(withIdentifier: id),
              let reminder = item as? EKReminder else {
            throw Abort(.notFound, reason: "Reminder not found")
        }
        
        try store.remove(reminder, commit: true)
        return .noContent
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

// MARK: - OpenAPI Specification

private let swaggerJSON = """
{"openapi":"3.0.3","info":{"title":"Reminders Server API","description":"API for managing macOS Reminders with webhook notifications","version":"1.0.0"},"servers":[{"url":"http://localhost:9201","description":"Local development"},{"url":"http://192.168.1.40:9201","description":"Local network"}],"paths":{"/":{"get":{"summary":"Health check","tags":["Health"],"responses":{"200":{"description":"Server is running","content":{"text/plain":{"schema":{"type":"string","example":"It works!"}}}}}}},"/reminders":{"get":{"summary":"Get all incomplete reminders","tags":["Reminders"],"responses":{"200":{"description":"List of reminders","content":{"application/json":{"schema":{"type":"array","items":{"$ref":"#/components/schemas/Reminder"}}}}},"403":{"description":"Reminders access denied"}}},"post":{"summary":"Create a new reminder","tags":["Reminders"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/CreateReminder"}}}},"responses":{"200":{"description":"Reminder created","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Reminder"}}}},"400":{"description":"Invalid request"},"403":{"description":"Reminders access denied"}}}},"/reminders/{id}":{"get":{"summary":"Get a specific reminder","tags":["Reminders"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"},"description":"Reminder ID"}],"responses":{"200":{"description":"Reminder details","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Reminder"}}}},"404":{"description":"Reminder not found"}}},"delete":{"summary":"Delete a reminder","tags":["Reminders"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"},"description":"Reminder ID"}],"responses":{"204":{"description":"Reminder deleted"},"404":{"description":"Reminder not found"}}}},"/reminders/{id}/complete":{"post":{"summary":"Mark a reminder as completed","tags":["Reminders"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string"},"description":"Reminder ID"}],"responses":{"200":{"description":"Reminder marked as completed","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Reminder"}}}},"404":{"description":"Reminder not found"}}}},"/webhooks":{"get":{"summary":"List all webhooks","tags":["Webhooks"],"responses":{"200":{"description":"List of webhooks","content":{"application/json":{"schema":{"type":"array","items":{"$ref":"#/components/schemas/Webhook"}}}}}}},"post":{"summary":"Create a new webhook subscription","tags":["Webhooks"],"requestBody":{"required":true,"content":{"application/json":{"schema":{"$ref":"#/components/schemas/CreateWebhook"}}}},"responses":{"200":{"description":"Webhook created","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Webhook"}}}},"400":{"description":"Invalid URL"}}}},"/webhooks/{id}":{"get":{"summary":"Get a specific webhook","tags":["Webhooks"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string","format":"uuid"},"description":"Webhook ID"}],"responses":{"200":{"description":"Webhook details","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Webhook"}}}},"404":{"description":"Webhook not found"}}},"delete":{"summary":"Delete a webhook","tags":["Webhooks"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string","format":"uuid"},"description":"Webhook ID"}],"responses":{"204":{"description":"Webhook deleted"},"404":{"description":"Webhook not found"}}}},"/webhooks/{id}/test":{"post":{"summary":"Send a test webhook payload","tags":["Webhooks"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string","format":"uuid"},"description":"Webhook ID"}],"responses":{"200":{"description":"Test result","content":{"application/json":{"schema":{"type":"object","properties":{"success":{"type":"boolean"}}}}}},"404":{"description":"Webhook not found"}}}},"/webhooks/{id}/toggle":{"patch":{"summary":"Toggle webhook active status","tags":["Webhooks"],"parameters":[{"name":"id","in":"path","required":true,"schema":{"type":"string","format":"uuid"},"description":"Webhook ID"}],"responses":{"200":{"description":"Webhook toggled","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Webhook"}}}},"404":{"description":"Webhook not found"}}}}},"components":{"schemas":{"Reminder":{"type":"object","properties":{"id":{"type":"string","description":"Unique reminder identifier"},"title":{"type":"string","description":"Reminder title"},"listName":{"type":"string","description":"Name of the reminder list"},"isCompleted":{"type":"boolean","description":"Whether the reminder is completed"},"dueDate":{"type":"string","format":"date-time","nullable":true,"description":"Due date for the reminder"},"notes":{"type":"string","nullable":true,"description":"Additional notes"}},"required":["id","title","listName"]},"CreateReminder":{"type":"object","properties":{"title":{"type":"string","description":"Reminder title"},"listName":{"type":"string","nullable":true,"description":"Name of the list to add to (uses default if not specified)"},"notes":{"type":"string","nullable":true,"description":"Additional notes"},"dueDate":{"type":"string","format":"date-time","nullable":true,"description":"Due date for the reminder"}},"required":["title"]},"Webhook":{"type":"object","properties":{"id":{"type":"string","format":"uuid","description":"Unique webhook identifier"},"url":{"type":"string","format":"uri","description":"URL to send webhook notifications to"},"reminderID":{"type":"string","nullable":true,"description":"Filter to specific reminder ID (null = all reminders)"},"listName":{"type":"string","nullable":true,"description":"Filter to specific list name (null = all lists)"},"events":{"type":"array","items":{"type":"string","enum":["created","updated","completed","deleted"]},"description":"Event types to subscribe to"},"active":{"type":"boolean","description":"Whether the webhook is active"},"createdAt":{"type":"string","format":"date-time","description":"When the webhook was created"}},"required":["id","url","events","active"]},"CreateWebhook":{"type":"object","properties":{"url":{"type":"string","format":"uri","description":"URL to send webhook notifications to"},"secret":{"type":"string","nullable":true,"description":"Secret for HMAC signature verification"},"reminderID":{"type":"string","nullable":true,"description":"Filter to specific reminder ID"},"listName":{"type":"string","nullable":true,"description":"Filter to specific list name"},"events":{"type":"array","items":{"type":"string","enum":["created","updated","completed","deleted"]},"description":"Event types to subscribe to (default: all)"}},"required":["url"]},"WebhookPayload":{"type":"object","description":"Payload sent to webhook URLs","properties":{"event":{"type":"string","description":"Event type (e.g., reminder.created, reminder.updated)","example":"reminder.created"},"timestamp":{"type":"string","format":"date-time","description":"When the event occurred"},"reminder":{"$ref":"#/components/schemas/ReminderSnapshot"},"previousState":{"$ref":"#/components/schemas/ReminderSnapshot","nullable":true,"description":"Previous state (for updates/deletes)"}}},"ReminderSnapshot":{"type":"object","properties":{"reminderID":{"type":"string"},"title":{"type":"string"},"listName":{"type":"string"},"isCompleted":{"type":"boolean"},"dueDate":{"type":"string","format":"date-time","nullable":true}}}}},"tags":[{"name":"Health","description":"Health check endpoints"},{"name":"Reminders","description":"Manage macOS Reminders"},{"name":"Webhooks","description":"Webhook subscriptions for reminder changes"}]}
"""

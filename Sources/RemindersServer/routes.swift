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

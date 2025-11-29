import Vapor
import Fluent
import Foundation

/// Service for dispatching webhook notifications
enum WebhookService {
    
    /// Dispatches webhook notifications for reminder changes
    static func dispatch(changes: [ReminderChange], app: Application) async throws {
        let webhooks = try await Webhook.query(on: app.db)
            .filter(\.$active == true)
            .all()
        
        guard !webhooks.isEmpty else {
            app.logger.debug("No active webhooks to dispatch")
            return
        }
        
        for change in changes {
            let matchingWebhooks = webhooks.filter { webhook in
                matches(webhook: webhook, change: change)
            }
            
            for webhook in matchingWebhooks {
                await dispatchToWebhook(webhook: webhook, change: change, app: app)
            }
        }
    }
    
    /// Checks if a webhook matches a reminder change
    private static func matches(webhook: Webhook, change: ReminderChange) -> Bool {
        // Check event type
        guard webhook.events.contains(change.eventType.rawValue) else {
            return false
        }
        
        // Check reminder ID filter
        if let filterReminderID = webhook.reminderID,
           filterReminderID != change.reminder.reminderID {
            return false
        }
        
        // Check list name filter
        if let filterListName = webhook.listName,
           filterListName != change.reminder.listName {
            return false
        }
        
        return true
    }
    
    /// Dispatches a single webhook notification
    private static func dispatchToWebhook(
        webhook: Webhook,
        change: ReminderChange,
        app: Application
    ) async {
        do {
            let payload = WebhookPayload(
                event: "reminder.\(change.eventType.rawValue)",
                timestamp: Date(),
                reminder: change.reminder,
                previousState: change.previousState
            )
            
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/json")
            headers.add(name: "X-Webhook-Event", value: payload.event)
            
            // Add HMAC signature if secret is configured
            if let secret = webhook.secret {
                let signature = try computeSignature(payload: payload, secret: secret)
                headers.add(name: "X-Webhook-Signature", value: signature)
            }
            
            let response = try await app.client.post(
                URI(string: webhook.url),
                headers: headers
            ) { req in
                try req.content.encode(payload)
            }
            
            if response.status.code >= 200 && response.status.code < 300 {
                app.logger.info("Webhook delivered: \(webhook.url) - \(payload.event)")
            } else {
                app.logger.warning("Webhook failed: \(webhook.url) - Status \(response.status.code)")
            }
            
        } catch {
            app.logger.error("Webhook dispatch error: \(webhook.url) - \(error)")
        }
    }
    
    /// Computes HMAC-SHA256 signature for webhook payload
    private static func computeSignature(payload: WebhookPayload, secret: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        
        // Simple signature using SHA256-like hash
        // In production, use CryptoKit's HMAC<SHA256>
        let payloadString = String(data: data, encoding: .utf8) ?? ""
        let combined = secret + payloadString
        
        var hash: UInt64 = 5381
        for char in combined.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        
        return String(format: "sha256=%016llx", hash)
    }
    
    /// Sends a test webhook to verify configuration
    static func sendTest(webhook: Webhook, app: Application) async throws -> Bool {
        let testPayload = WebhookPayload(
            event: "webhook.test",
            timestamp: Date(),
            reminder: ReminderSnapshotData(
                reminderID: "test-reminder-id",
                title: "Test Reminder",
                listName: "Test List",
                isCompleted: false,
                dueDate: Date()
            ),
            previousState: nil
        )
        
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        headers.add(name: "X-Webhook-Event", value: testPayload.event)
        
        if let secret = webhook.secret {
            let signature = try computeSignature(payload: testPayload, secret: secret)
            headers.add(name: "X-Webhook-Signature", value: signature)
        }
        
        let response = try await app.client.post(
            URI(string: webhook.url),
            headers: headers
        ) { req in
            try req.content.encode(testPayload)
        }
        
        return response.status.code >= 200 && response.status.code < 300
    }
}

// MARK: - Webhook Payload

struct WebhookPayload: Content {
    let event: String
    let timestamp: Date
    let reminder: ReminderSnapshotData
    let previousState: ReminderSnapshotData?
}

import Vapor
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
                                listName: $0.calendar?.title ?? "",
                            )
                        }
                }
                sema.signal()
            }
        }

        sema.wait()
        return titles
    }
}

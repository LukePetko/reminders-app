import Vapor
import Fluent
import FluentPostgresDriver

// configures your application
public func configure(_ app: Application) async throws {
    // Serve files from /Public folder (swagger.json)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 9201

    let dbHostname = Environment.get("DB_HOST") ?? "127.0.0.1"
    let dbPort = Environment.get("DB_PORT").flatMap(Int.init) ?? 5432
    let dbUsername = Environment.get("DB_USER") ?? "postgres"
    let dbPassword = Environment.get("DB_PASS") ?? ""
    let dbDatabase = Environment.get("DB_NAME") ?? "reminders"
    
    print("Connecting to DB")
    print("Host:", dbHostname)
    print("Port:", dbPort)
    print("User:", dbUsername)
    print("Pass:", dbPassword.isEmpty ? "<empty>" : "<redacted>")
    print("DB:", dbDatabase)

    app.databases.use(
        .postgres(
            hostname: dbHostname,
            port: dbPort,
            username: dbUsername,
            password: dbPassword,
            database: dbDatabase
        ),
        as: .psql
    )
    
    // Register migrations
    app.migrations.add(CreateWebhook())
    app.migrations.add(CreateReminderSnapshot())
    
    // Run migrations automatically
    try await app.autoMigrate()
    
    // Start ReminderWatcher
    let watcher = ReminderWatcher(app: app)
    app.reminderWatcher = watcher
    try await watcher.start()
    
    // register routes
    try routes(app)
}

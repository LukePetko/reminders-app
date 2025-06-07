import Vapor
import Fluent
import FluentMySQLDriver

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    app.http.server.configuration.port = 9201

    let dbHostname = Environment.get("DB_HOST") ?? "127.0.0.1"
    let dbUsername = Environment.get("DB_USER") ?? "root"
    let dbPassword = Environment.get("DB_PASS") ?? ""
    let dbDatabase = Environment.get("DB_NAME") ?? "test"
    
    var tls = TLSConfiguration.makeClientConfiguration()
    tls.certificateVerification = .none
    // tls.trustRoots = .file("Resources/SSL/ca.pem")
    // tls.trustRoots = .file("/Users/lukaspetko/Projects/reminders-server/Resources/SSL/ca.pem")
    
    print("🔌 Connecting to DB")
    print("Host:", dbHostname)
    print("User:", dbUsername)
    print("Pass:", dbPassword.isEmpty ? "<empty>" : "<redacted>")
    print("DB:", dbDatabase)

    print(dbHostname, dbUsername)
    print("Attempting to connect to MySQL at \(dbHostname):3306")
    print("Current working directory: \(FileManager.default.currentDirectoryPath)")

    app.databases.use(.mysql(hostname: dbHostname, port:3306, username: dbUsername, password: dbPassword, database: dbDatabase, tlsConfiguration: tls), as: .mysql)

    // register routes
    try routes(app)
}

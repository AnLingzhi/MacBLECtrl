import Vapor
import Logging

// Removed @main attribute from here
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env) // Use & for ampersand in XML

        // Use Application.make for async initialization
        let app = try await Application.make(env)
        // defer { app.shutdown() } // Removing defer shutdown again to address compiler warning

        do {
            try await configure(app) // Call the configuration function
        } catch {
            app.logger.critical("Failed to configure application: \(error)")
            throw error // Re-throw to stop execution if configuration fails
        }

        // Log the server address - Direct access should be fine
        let host = app.http.server.configuration.hostname
        let port = app.http.server.configuration.port
        app.logger.info("Server starting on http://\(host):\(port)")

        // Use execute() for async startup
        // No need to await here as the call below handles the run loop
        try await app.execute()
    }
}

// Call the async main function to start the application
// This replaces the need for @main when using async main
try await Entrypoint.main() // Add try to handle potential throws

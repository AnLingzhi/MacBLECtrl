import Vapor
import CoreBluetooth
import Logging // Vapor uses swift-log

// configures your application
public func configure(_ app: Application) async throws {
    // Serves files from `Public/` directory
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Initialize BluetoothManager
    let bluetoothManager = BluetoothManager(app: app)
    app.bluetoothManager = bluetoothManager // Store it in Application storage

    // Start Bluetooth initialization asynchronously
    // We don't await this here because configure needs to return quickly.
    // The manager will handle its state internally.
    Task {
        await bluetoothManager.initializeManager()
        // Optionally start scanning immediately after initialization
        // await bluetoothManager.startScan()
        app.logger.info("BluetoothManager initialization sequence started.")
    }

    // register routes
    try routes(app)

    // Configure hostname and port (optional, defaults to 127.0.0.1:8080)
    app.http.server.configuration.hostname = "0.0.0.0" // Listen on all interfaces
    app.http.server.configuration.port = 8080
}

import Vapor
import CoreBluetooth

// Define structures for API responses
struct DeviceInfo: Content {
    let name: String?
    let identifier: String // UUID string
    let rssi: Int? // Optional RSSI
    let isConnectable: Bool? // Optional connectable status
}

struct DeviceDetail: Content {
    let name: String?
    let identifier: String // UUID string
    let batteryLevel: Int? // Optional battery level
    let isConnected: Bool
    // Add other relevant details if needed
}

func routes(_ app: Application) throws {

    // Basic health check endpoint
    app.get { req async -> String in
        "MacBLECtrl Service is running!"
    }

    // Endpoint to get the list of discovered devices
    app.get("devices") { req -> [DeviceInfo] in
        guard let manager = req.application.bluetoothManager else {
            throw Abort(.internalServerError, reason: "BluetoothManager not initialized")
        }
        // Access the discovered peripherals from the manager
        // Note: This requires BluetoothManager to store discovered devices
        // in a thread-safe way accessible here.
        let devices = await manager.getDiscoveredDevices()
        return devices.map { deviceInfo in
            DeviceInfo(
                name: deviceInfo.name,
                identifier: deviceInfo.identifier,
                rssi: deviceInfo.rssi,
                isConnectable: deviceInfo.isConnectable
            )
        }
    }

    // Endpoint to get details (including battery) for a specific device
    app.get("device", ":identifier") { req -> DeviceDetail in
        guard let identifierString = req.parameters.get("identifier"),
              let identifier = UUID(uuidString: identifierString) else {
            throw Abort(.badRequest, reason: "Invalid or missing device identifier")
        }

        guard let manager = req.application.bluetoothManager else {
            throw Abort(.internalServerError, reason: "BluetoothManager not initialized")
        }

        // Request battery level for the specific device
        // This requires BluetoothManager to handle connection and fetching
        let detail = try await manager.getDeviceDetails(identifier: identifier)

        return DeviceDetail(
            name: detail.name,
            identifier: detail.identifier,
            batteryLevel: detail.batteryLevel,
            isConnected: detail.isConnected
            // Map other details here
        )
    }

    // Optional: Endpoint to trigger a new scan (might be useful)
    app.post("scan") { req -> HTTPStatus in
        guard let manager = req.application.bluetoothManager else {
            throw Abort(.internalServerError, reason: "BluetoothManager not initialized")
        }
        // Trigger a scan asynchronously
        await manager.startScan()
        return .accepted // Indicate the scan has started
    }
}

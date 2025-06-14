import Vapor
import CoreBluetooth

// Define structures for API responses
struct DeviceInfo: Content {
    let name: String?
    let identifier: String // UUID string
    let rssi: Int? // Optional RSSI
    let isConnectable: Bool? // Optional connectable status
}

// Add this new struct
struct DeviceListResponse: Content {
   let devices: [DeviceInfo]
}

struct DeviceDetail: Content {
    let name: String?
    let identifier: String // UUID string
    let batteryLevel: Int? // Optional battery level
    let isConnected: Bool
    // Add other relevant details if needed

    // Custom CodingKeys to ensure all keys are present in the JSON output
    private enum CodingKeys: String, CodingKey {
        case name, identifier, batteryLevel, isConnected
    }

    // Custom encoder to write `null` for nil values
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.identifier, forKey: .identifier)
        try container.encode(self.isConnected, forKey: .isConnected)

        // Explicitly encode nil as null for name and batteryLevel
        try container.encodeIfPresent(self.name, forKey: .name)
        if self.name == nil {
            try container.encodeNil(forKey: .name)
        }
        
        try container.encodeIfPresent(self.batteryLevel, forKey: .batteryLevel)
        if self.batteryLevel == nil {
            try container.encodeNil(forKey: .batteryLevel)
        }
    }
}

func routes(_ app: Application) throws {

    // Basic health check endpoint
    app.get { req async -> String in
        "MacBLECtrl Service is running!"
    }

    // Endpoint to get the list of discovered devices
    app.get("devices") { req -> DeviceListResponse in // <-- Change return type
        guard let manager = req.application.bluetoothManager else {
            throw Abort(.internalServerError, reason: "BluetoothManager not initialized")
        }
        // Access the discovered peripherals from the manager
        // Note: This requires BluetoothManager to store discovered devices
        // in a thread-safe way accessible here.
        let devices = await manager.getDiscoveredDevices()
        let deviceInfos = devices.map { deviceInfo in
            DeviceInfo(
                name: deviceInfo.name,
                identifier: deviceInfo.identifier,
                rssi: deviceInfo.rssi,
                isConnectable: deviceInfo.isConnectable
            )
        }
        return DeviceListResponse(devices: deviceInfos) // <-- Return the wrapped response
    }

    // Endpoint to get details (including battery) for a specific device
    app.get("device", ":identifier") { req -> DeviceDetail in
        guard let identifierString = req.parameters.get("identifier"),
              let identifier = UUID(uuidString: identifierString) else {
            throw Abort(.badRequest, reason: "Invalid or missing device identifier")
        }

        guard let manager = req.application.bluetoothManager else {
            req.logger.error("BluetoothManager not initialized for device request.")
            throw Abort(.internalServerError, reason: "BluetoothManager not initialized")
        }

        do {
            // Request battery level for the specific device
            let detail = try await manager.getDeviceDetails(identifier: identifier)
            return DeviceDetail(
                name: detail.name,
                identifier: detail.identifier,
                batteryLevel: detail.batteryLevel,
                isConnected: detail.isConnected
            )
        } catch {
            // If any error occurs (timeout, not found, etc.), log it and return a default response
            req.logger.warning("Failed to get details for \(identifierString): \(error.localizedDescription). Returning default values.")
            return DeviceDetail(
                name: nil, // Name is unknown
                identifier: identifierString,
                batteryLevel: nil, // Battery level is unknown
                isConnected: false // Definitely not connected
            )
        }
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

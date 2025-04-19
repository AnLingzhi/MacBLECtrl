import Foundation
import CoreBluetooth
import Vapor // For Application, Logger, EventLoopFuture, Abort etc.
import Logging

// Define internal structures to hold device state
struct DiscoveredDevice {
    let peripheral: CBPeripheral
    var name: String?
    var rssi: Int?
    var advertisementData: [String: Any]
    var lastSeen: Date
    var isConnectable: Bool? // From advertisement data if available

    var identifierString: String { peripheral.identifier.uuidString }
}

struct ConnectedDeviceDetails {
    let peripheral: CBPeripheral
    var name: String?
    var batteryLevel: Int?
    var isConnected: Bool

    var identifierString: String { peripheral.identifier.uuidString }
}

// Using an actor for thread-safe access to shared state
actor BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let app: Application // Reference to the Vapor application
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [UUID: DiscoveredDevice] = [:]
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var batteryPromises: [UUID: EventLoopPromise<Int?>] = [:] // Promises for battery requests
    private var scanContinuation: CheckedContinuation<Void, Never>? // For async scan start

    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryCharacteristicUUID = CBUUID(string: "2A19")

    private var logger: Logger { app.logger } // Use Vapor's logger

    // Initialization
    init(app: Application) {
        self.app = app
        super.init()
        // Logger access moved to initializeManager to avoid nonisolated context issue
    }

    // Public method to initialize the CBCentralManager
    func initializeManager() async { // Make async to use logger safely
        logger.info("BluetoothManager Actor Initialized & Initializing CBCentralManager...")
        // Initialize CBCentralManager within the actor's context,
        // but specify DispatchQueue.main for callbacks.
        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        // State update will be handled by the delegate method.
    }

    // MARK: - API Facing Methods

    /// Starts a Bluetooth scan.
    func startScan() async {
        guard centralManager != nil else {
             logger.error("Central Manager not initialized yet.")
             return
        }
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot start scan: Bluetooth is not powered on (\(centralManager.state.rawValue)).")
            // Optionally wait for power on? For a service, maybe just log.
            return
        }

        logger.info("Starting Bluetooth scan...")
        // Clear old peripherals before starting a new scan? Optional, depends on desired behavior.
        // discoveredPeripherals.removeAll()

        // Scan for all devices
        let scanOptions: [String: Any]? = [CBCentralManagerScanOptionAllowDuplicatesKey: false] // Don't allow duplicates for API listing
        centralManager.scanForPeripherals(withServices: nil, options: scanOptions)

        // Optionally stop scan after some time? For a service, maybe scan continuously?
        // Or provide a stopScan endpoint. For now, let it run.
    }

    /// Stops an ongoing Bluetooth scan.
    func stopScan() {
         guard centralManager != nil else { return }
         if centralManager.isScanning {
              logger.info("Stopping Bluetooth scan.")
              centralManager.stopScan()
         }
    }

    /// Returns a list of discovered devices.
    func getDiscoveredDevices() -> [DeviceInfo] {
        // Return a snapshot of the current state
        return discoveredPeripherals.values.map { device in
            DeviceInfo(
                name: device.name,
                identifier: device.identifierString,
                rssi: device.rssi,
                isConnectable: device.isConnectable
            )
        }
    }

    /// Attempts to connect to a device and retrieve its details (including battery).
    func getDeviceDetails(identifier: UUID) async throws -> DeviceDetail {
        guard centralManager != nil else {
             logger.error("Central Manager not initialized yet.")
             throw Abort(.internalServerError, reason: "BluetoothManager not initialized")
        }
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot connect: Bluetooth is not powered on (\(centralManager.state.rawValue)).")
            throw Abort(.serviceUnavailable, reason: "Bluetooth not powered on")
        }

        // Check if we already know about this peripheral from scanning
        guard let discoveredDevice = discoveredPeripherals[identifier] else {
            logger.warning("Device \(identifier) not found in discovered list. Trying to retrieve.")
            // Attempt to retrieve peripheral directly if known to the system
             let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [identifier])
             guard let peripheral = knownPeripherals.first else {
                 throw Abort(.notFound, reason: "Device \(identifier) not found or not discoverable.")
             }
             // Add to discovered list temporarily if retrieved
             discoveredPeripherals[identifier] = DiscoveredDevice(peripheral: peripheral, name: peripheral.name, rssi: nil, advertisementData: [:], lastSeen: Date(), isConnectable: nil)
             return try await connectAndFetchDetails(peripheral: peripheral)
        }

        let peripheral = discoveredDevice.peripheral

        // Check if already connected
        if peripheral.state == .connected {
            logger.info("Device \(identifier) already connected. Fetching battery level...")
            // If already connected, try reading battery directly
            return try await fetchBatteryLevel(peripheral: peripheral)
        } else {
            logger.info("Connecting to device \(identifier)...")
            // Create a promise to await the battery level result
            let promise = app.eventLoopGroup.next().makePromise(of: Int?.self)
            batteryPromises[identifier] = promise

            centralManager.connect(peripheral, options: nil)

            // Wait for the promise to complete (or timeout)
            do {
                // Add a timeout mechanism
                let batteryLevel = try await promise.futureResult.get() // Add timeout here if needed
                logger.info("Successfully fetched battery level (\(batteryLevel ?? -1)) for \(identifier)")
                 return DeviceDetail(
                    name: peripheral.name,
                    identifier: identifier.uuidString,
                    batteryLevel: batteryLevel,
                    isConnected: peripheral.state == .connected // Re-check state
                )
            } catch {
                logger.error("Failed to get battery level for \(identifier): \(error)")
                // Clean up promise
                batteryPromises.removeValue(forKey: identifier)
                // Disconnect if connection attempt failed or timed out
                if peripheral.state == .connecting || peripheral.state == .connected {
                     centralManager.cancelPeripheralConnection(peripheral)
                }
                throw Abort(.internalServerError, reason: "Failed to retrieve battery level: \(error.localizedDescription)")
            }
        }
    }

    // Helper to fetch battery level for an already connected peripheral
    private func fetchBatteryLevel(peripheral: CBPeripheral) async throws -> DeviceDetail {
        guard peripheral.state == .connected else {
             throw Abort(.conflict, reason: "Peripheral is not connected.")
        }
        logger.info("Fetching battery for already connected peripheral \(peripheral.identifier)")
        let promise = app.eventLoopGroup.next().makePromise(of: Int?.self)
        batteryPromises[peripheral.identifier] = promise

        // Ensure services are discovered before reading
        if let batteryService = peripheral.services?.first(where: { $0.uuid == batteryServiceUUID }) {
             if let batteryChar = batteryService.characteristics?.first(where: { $0.uuid == batteryCharacteristicUUID }) {
                  logger.info("Battery characteristic already discovered for \(peripheral.identifier). Reading value.")
                  peripheral.readValue(for: batteryChar)
             } else {
                  logger.info("Discovering characteristics for battery service on \(peripheral.identifier)...")
                  peripheral.discoverCharacteristics([batteryCharacteristicUUID], for: batteryService)
             }
        } else {
             logger.info("Discovering battery service on \(peripheral.identifier)...")
             peripheral.discoverServices([batteryServiceUUID])
        }

        // Wait for the promise
        do {
            let batteryLevel = try await promise.futureResult.get() // Add timeout
            return DeviceDetail(
                name: peripheral.name,
                identifier: peripheral.identifier.uuidString,
                batteryLevel: batteryLevel,
                isConnected: true
            )
        } catch {
            logger.error("Failed to get battery level for \(peripheral.identifier): \(error)")
            batteryPromises.removeValue(forKey: peripheral.identifier)
            // Don't necessarily disconnect here, maybe the caller wants to retry?
            throw Abort(.internalServerError, reason: "Failed to retrieve battery level: \(error.localizedDescription)")
        }
    }

     // Helper to handle connection and detail fetching logic
    private func connectAndFetchDetails(peripheral: CBPeripheral) async throws -> DeviceDetail {
        logger.info("Connecting to peripheral \(peripheral.identifier) for details...")
        let promise = app.eventLoopGroup.next().makePromise(of: Int?.self)
        batteryPromises[peripheral.identifier] = promise

        centralManager.connect(peripheral, options: nil)

        do {
            let batteryLevel = try await promise.futureResult.get() // Add timeout
            logger.info("Successfully fetched battery level (\(batteryLevel ?? -1)) for \(peripheral.identifier)")
            return DeviceDetail(
                name: peripheral.name,
                identifier: peripheral.identifier.uuidString,
                batteryLevel: batteryLevel,
                isConnected: peripheral.state == .connected
            )
        } catch {
            logger.error("Failed to get battery level for \(peripheral.identifier): \(error)")
            batteryPromises.removeValue(forKey: peripheral.identifier)
            if peripheral.state == .connecting || peripheral.state == .connected {
                centralManager.cancelPeripheralConnection(peripheral)
            }
            throw Abort(.internalServerError, reason: "Failed to retrieve battery level: \(error.localizedDescription)")
        }
    }


    // MARK: - CBCentralManagerDelegate

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Run actor-isolated code asynchronously
        Task {
            await self.handleCentralManagerStateUpdate(central.state)
        }
    }

    private func handleCentralManagerStateUpdate(_ state: CBManagerState) {
         logger.info("Bluetooth state updated: \(state.rawValue)")
         switch state {
         case .poweredOn:
             logger.info("Bluetooth is Powered On.")
             // Signal that scanning can start if requested
             scanContinuation?.resume()
             scanContinuation = nil
             // Optionally start scanning automatically?
             // Task { await startScan() }
         case .poweredOff:
             logger.warning("Bluetooth is Powered Off.")
             // Clean up state? Stop scanning?
             discoveredPeripherals.removeAll()
             connectedPeripherals.removeAll()
             // Fail any pending promises?
             batteryPromises.values.forEach { $0.fail(Abort(.serviceUnavailable, reason: "Bluetooth powered off")) }
             batteryPromises.removeAll()
         case .resetting:
             logger.warning("Bluetooth is Resetting.")
             // Handle similarly to poweredOff
         case .unauthorized:
             logger.error("Bluetooth usage unauthorized. Check System Preferences -> Security & Privacy -> Bluetooth.")
             // Fail pending promises
             batteryPromises.values.forEach { $0.fail(Abort(.forbidden, reason: "Bluetooth unauthorized")) }
             batteryPromises.removeAll()
         case .unsupported:
             logger.error("Bluetooth is not supported on this device.")
             // Fail pending promises
             batteryPromises.values.forEach { $0.fail(Abort(.internalServerError, reason: "Bluetooth not supported")) }
             batteryPromises.removeAll()
         case .unknown:
             logger.warning("Bluetooth state is Unknown.")
         @unknown default:
             logger.warning("Unknown Bluetooth state: \(state.rawValue)")
         }
    }


    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task {
            // Extract necessary data from peripheral and advertisementData
            // 不需要存储这些变量，直接传递给处理方法
            let advertisementDataCopy = advertisementData // Assuming Dictionary is value type and safe to copy

            await self.handleDiscovery(peripheral: peripheral, advertisementData: advertisementDataCopy, rssi: RSSI)
        }
    }

    private func handleDiscovery(peripheral: CBPeripheral, advertisementData: [String : Any], rssi: NSNumber) {
        let identifier = peripheral.identifier
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let isConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool

        // Update or add the peripheral info
        let device = DiscoveredDevice(
            peripheral: peripheral,
            name: name,
            rssi: rssi.intValue,
            advertisementData: advertisementData,
            lastSeen: Date(),
            isConnectable: isConnectable
        )
        discoveredPeripherals[identifier] = device

        // Log discovery
        // logger.debug("Discovered: \(name ?? "N/A") (\(identifier)), RSSI: \(rssi.intValue)")
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task {
            await self.handleConnection(peripheral: peripheral)
        }
    }

     private func handleConnection(peripheral: CBPeripheral) {
         logger.info("Connected to: \(peripheral.name ?? "N/A") (\(peripheral.identifier))")
         connectedPeripherals[peripheral.identifier] = peripheral
         peripheral.delegate = self // Set delegate *within the actor*

         // Discover battery service
         logger.info("Discovering services for \(peripheral.identifier)...")
         peripheral.discoverServices([batteryServiceUUID])
     }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task {
            await self.handleFailedConnection(peripheral: peripheral, error: error)
        }
    }

    private func handleFailedConnection(peripheral: CBPeripheral, error: Error?) {
        let errorDescription = error?.localizedDescription ?? "Unknown error"
        logger.error("Failed to connect to \(peripheral.identifier): \(errorDescription)")
        // Fail the corresponding promise if one exists
        if let promise = batteryPromises.removeValue(forKey: peripheral.identifier) {
            // Use a valid HTTP status or a generic error
            promise.fail(error ?? Abort(.internalServerError, reason: "Failed to connect"))
        }
    }

     nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
         Task {
             await self.handleDisconnection(peripheral: peripheral, error: error)
         }
     }

    private func handleDisconnection(peripheral: CBPeripheral, error: Error?) {
        let reason = error == nil ? "normally" : "with error: \(error!.localizedDescription)"
        logger.info("Disconnected from \(peripheral.identifier) \(reason)")
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        // Fail any pending promise for this peripheral? Or assume it was fulfilled?
        // If a request was in progress and it disconnects, it should probably fail.
        if let promise = batteryPromises.removeValue(forKey: peripheral.identifier) {
            // Use a valid HTTP status or a generic error
            promise.fail(error ?? Abort(.internalServerError, reason: "Peripheral disconnected unexpectedly"))
        }
    }

    // MARK: - CBPeripheralDelegate

    // Note: Peripheral delegate methods are called on the main queue specified for the CentralManager.
    // We need to hop back to the actor's context to modify state safely.

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task {
            await self.handleServiceDiscovery(peripheral: peripheral, error: error)
        }
    }

    private func handleServiceDiscovery(peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.error("Error discovering services for \(peripheral.identifier): \(error.localizedDescription)")
            failBatteryPromise(for: peripheral.identifier, error: error)
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let services = peripheral.services else {
            logger.warning("No services found for \(peripheral.identifier)")
            failBatteryPromise(for: peripheral.identifier, error: Abort(.notFound, reason: "No services found"))
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        if let batteryService = services.first(where: { $0.uuid == batteryServiceUUID }) {
            logger.info("Found Battery Service for \(peripheral.identifier). Discovering characteristics...")
            peripheral.discoverCharacteristics([batteryCharacteristicUUID], for: batteryService)
        } else {
            logger.warning("Battery Service (\(batteryServiceUUID.uuidString)) not found for \(peripheral.identifier)")
            failBatteryPromise(for: peripheral.identifier, error: Abort(.notFound, reason: "Battery service not found"))
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task {
            // 移除未使用的变量
            _ = peripheral.identifier
            _ = service.uuid
            await self.handleCharacteristicDiscovery(peripheral: peripheral, service: service, error: error)
        }
    }

    private func handleCharacteristicDiscovery(peripheral: CBPeripheral, service: CBService, error: Error?) {
        if let error = error {
            logger.error("Error discovering characteristics for \(peripheral.identifier): \(error.localizedDescription)")
            failBatteryPromise(for: peripheral.identifier, error: error)
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        guard let characteristics = service.characteristics else {
            logger.warning("No characteristics found for service \(service.uuid) on \(peripheral.identifier)")
            failBatteryPromise(for: peripheral.identifier, error: Abort(.notFound, reason: "No characteristics found"))
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        if let batteryChar = characteristics.first(where: { $0.uuid == batteryCharacteristicUUID }) {
            logger.info("Found Battery Characteristic for \(peripheral.identifier). Reading value...")
            peripheral.readValue(for: batteryChar)
        } else {
            logger.warning("Battery Characteristic (\(batteryCharacteristicUUID.uuidString)) not found for \(peripheral.identifier)")
            failBatteryPromise(for: peripheral.identifier, error: Abort(.notFound, reason: "Battery characteristic not found"))
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task {
            // 移除未使用的变量
            _ = peripheral.identifier
            _ = characteristic.uuid
            _ = characteristic.value
            await self.handleValueUpdate(peripheral: peripheral, characteristic: characteristic, error: error)
        }
    }

    private func handleValueUpdate(peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        let peripheralID = peripheral.identifier

        if let error = error {
            logger.error("Error reading value for \(characteristic.uuid) on \(peripheralID): \(error.localizedDescription)")
            failBatteryPromise(for: peripheralID, error: error)
            // Keep connected or disconnect? Maybe just fail the promise.
            // centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        if characteristic.uuid == batteryCharacteristicUUID {
            guard let data = characteristic.value, !data.isEmpty else {
                logger.warning("Received empty data for battery characteristic on \(peripheralID)")
                failBatteryPromise(for: peripheralID, error: Abort(.noContent, reason: "Empty battery data"))
                return
            }

            let batteryLevel = Int(data[0])
            logger.info("Received Battery Level for \(peripheralID): \(batteryLevel)%")

            // Fulfill the promise
            if let promise = batteryPromises.removeValue(forKey: peripheralID) {
                promise.succeed(batteryLevel)
            } else {
                 logger.warning("Received battery level for \(peripheralID) but no promise was found.")
            }

            // Optional: Disconnect after reading? Or keep connected?
            // For a service, maybe keep connected for a short while? Or disconnect immediately.
            // logger.info("Disconnecting from \(peripheralID) after reading battery.")
            // centralManager.cancelPeripheralConnection(peripheral)

        } else {
            logger.warning("Received value update for unexpected characteristic \(characteristic.uuid) on \(peripheralID)")
        }
    }

    // Helper to fail a battery promise
    private func failBatteryPromise(for identifier: UUID, error: Error) {
        if let promise = batteryPromises.removeValue(forKey: identifier) {
            promise.fail(error)
        }
    }
}

// Helper extension for CBManagerState rawValue logging
extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "PoweredOff"
        case .poweredOn: return "PoweredOn"
        @unknown default: return "Unknown (\(rawValue))"
        }
    }
}

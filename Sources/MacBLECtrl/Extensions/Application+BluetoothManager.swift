import Vapor
import MacBLECtrl // Assuming your module name is MacBLECtrl

// Extend Application to hold our BluetoothManager instance
extension Application {
    struct BluetoothManagerKey: StorageKey {
        typealias Value = BluetoothManager
    }

    var bluetoothManager: BluetoothManager? {
        get {
            self.storage[BluetoothManagerKey.self]
        }
        set {
            self.storage[BluetoothManagerKey.self] = newValue
        }
    }
}

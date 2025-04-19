import Vapor
// 移除循环导入，因为该文件已经是MacBLECtrl模块的一部分

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

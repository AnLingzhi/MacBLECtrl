import Foundation
import CoreBluetooth

// 使用BluetoothManager.swift中的实现，这里重命名为LegacyBluetoothManager
class LegacyBluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var scanDuration: Int = 20 // 默认扫描时间20秒
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripheral: CBPeripheral?
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryCharacteristicUUID = CBUUID(string: "2A19")
    private var targetDeviceUUID: UUID?
    private var directConnect: Bool = false
    
    init(scanDuration: Int = 20, deviceUUID: String? = nil) {
        self.scanDuration = scanDuration
        if let uuidString = deviceUUID, let uuid = UUID(uuidString: uuidString) {
            self.targetDeviceUUID = uuid
            self.directConnect = true
            print("将直接连接到设备: \(uuidString)")
        }
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        if centralManager.state == .poweredOn {
            print("开始扫描附近的蓝牙设备...")
            print("蓝牙状态: 已开启，准备扫描")
            
            // 清空之前的设备列表
            discoveredPeripherals.removeAll()
            
            // 改进扫描选项：设置为允许重复发现以提高发现率
            // 不指定服务UUID，以便发现所有类型的设备
            let scanOptions: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
            
            print("扫描参数: \(scanOptions)")
            print("开始全频段扫描，不限制设备类型...")
            
            // 不指定服务UUID进行扫描，以发现所有设备
            centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
            
            // 使用用户指定的扫描时间
            print("扫描将持续\(scanDuration)秒...")
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(scanDuration)) { [weak self] in
                self?.stopScanningAndShowResults()
            }
        } else {
            print("蓝牙未开启，请打开蓝牙后重试")
        }
    }
    
    func stopScanningAndShowResults() {
        centralManager.stopScan()
        print("\n扫描完成，发现 \(discoveredPeripherals.count) 个设备:")
        
        if discoveredPeripherals.isEmpty {
            print("未发现任何蓝牙设备，请确保附近有蓝牙设备且处于可发现状态")
        } else {
            // 按信号强度排序设备列表（信号强度高的排在前面）
            let sortedPeripherals = discoveredPeripherals
            
            for (index, peripheral) in sortedPeripherals.enumerated() {
                let name = peripheral.name ?? "未命名设备"
                print("\(index + 1). \(name) [\(peripheral.identifier)]")
            }
        }
        
        // 添加重新扫描选项
        print("\n输入 'r' 重新扫描，或")
        
        if !discoveredPeripherals.isEmpty {
            print("\n请输入设备编号以连接并获取电量信息，或输入 'q' 退出:")
            if let input = readLine() {
                if input.lowercased() == "r" {
                    // 清空已发现的设备列表并重新开始扫描
                    print("\n重新开始扫描...")
                    discoveredPeripherals.removeAll()
                    startScanning()
                    return
                } else if input.lowercased() == "q" {
                    print("程序退出")
                    exit(0)
                } else if let deviceIndex = Int(input), deviceIndex > 0 && deviceIndex <= discoveredPeripherals.count {
                    let selectedPeripheral = discoveredPeripherals[deviceIndex - 1]
                    connectToPeripheral(selectedPeripheral)
                } else {
                    print("无效的设备编号，请重新输入或输入 'q' 退出:")
                    // 递归调用自身，让用户重新输入而不是直接退出
                    stopScanningAndShowResults()
                }
            } else {
                print("程序退出")
                exit(0)
            }
        } else {
            print("未发现设备，是否重新扫描？(y/n)")
            if let input = readLine(), input.lowercased() == "y" {
                startScanning()
            } else {
                print("程序退出")
                exit(0)
            }
        }
    }
    
    func connectToPeripheral(_ peripheral: CBPeripheral) {
        print("正在连接到设备: \(peripheral.name ?? "未知设备")...")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("蓝牙状态更新: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            if directConnect, let uuid = targetDeviceUUID {
                print("蓝牙已开启，正在直接连接到指定设备...")
                self.connectToDeviceWithUUID(uuid)
            } else {
                print("蓝牙已开启，开始扫描设备...")
                startScanning()
            }
        case .poweredOff:
            print("蓝牙已关闭，请开启蓝牙后重试")
            exit(1)
        case .resetting:
            print("蓝牙正在重置，请稍后重试")
            exit(1)
        case .unauthorized:
            print("蓝牙使用未授权，请检查系统权限设置")
            exit(1)
        case .unsupported:
            print("此设备不支持蓝牙功能")
            exit(1)
        case .unknown:
            print("蓝牙状态未知")
            exit(1)
        @unknown default:
            print("蓝牙状态: \(central.state)")
            exit(1)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // 增强设备发现日志，打印所有广播数据以便诊断
        print("检测到设备: ID=[\(peripheral.identifier)]")
        print("  - 名称: \(peripheral.name ?? "未命名设备")")
        print("  - 信号强度: \(RSSI) dBm")
        
        // 打印所有广播数据
        print("  - 广播数据:")
        for (key, value) in advertisementData {
            print("    * \(key): \(value)")
        }
        
        // 如果是直接连接模式且UUID匹配，立即连接
        if directConnect, let targetUUID = targetDeviceUUID, peripheral.identifier == targetUUID {
            centralManager.stopScan()
            print("找到目标设备，停止扫描并连接...")
            connectToPeripheral(peripheral)
            return
        }
        
        // 检查是否已存在该设备
        if !discoveredPeripherals.contains(peripheral) {
            discoveredPeripherals.append(peripheral)
            let deviceName = peripheral.name ?? "未命名设备"
            let signalStrength = "信号强度: \(RSSI) dBm"
            
            // 打印广播数据中的服务UUID信息
            var serviceInfo = ""
            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], !serviceUUIDs.isEmpty {
                serviceInfo = "，服务: \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))"
            }
            
            print("添加新设备: \(deviceName) [\(peripheral.identifier)] \(signalStrength)\(serviceInfo)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("已连接到设备: \(peripheral.name ?? "未知设备")")
        peripheral.discoverServices([batteryServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("连接失败: \(error?.localizedDescription ?? "未知错误")")
        exit(1)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("设备已断开连接")
        exit(0)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("服务发现失败: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == batteryServiceUUID {
                print("发现电池服务")
                peripheral.discoverCharacteristics([batteryCharacteristicUUID], for: service)
                return
            }
        }
        
        print("此设备不支持电池服务")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("特征发现失败: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == batteryCharacteristicUUID {
                print("发现电池电量特征")
                peripheral.readValue(for: characteristic)
                return
            }
        }
        
        print("此设备不支持电池电量特征")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("读取特征值失败: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        if characteristic.uuid == batteryCharacteristicUUID, let data = characteristic.value {
            let batteryLevel = data[0]
            print("\n设备信息:")
            print("名称: \(peripheral.name ?? "未知设备")")
            print("标识: \(peripheral.identifier)")
            print("电量: \(batteryLevel)%")
        }
        
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    // 直接连接到指定设备的方法
    func connectToDeviceWithUUID(_ uuid: UUID) {
        print("正在尝试直接连接到设备UUID: \(uuid)")
        
        // 尝试从系统已知设备中检索设备
        // 移除未使用的变量
        _ = [
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        
        // 使用retrievePeripherals方法尝试直接获取设备，无需扫描
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        
        if let peripheral = peripherals.first {
            print("找到已知设备，正在连接...")
            connectToPeripheral(peripheral)
        } else {
            print("无法直接连接到指定UUID的设备，设备可能不在系统已知设备列表中")
            print("将进行短时间扫描以查找设备...")
            
            // 如果无法直接连接，则进行短时间扫描
            let scanOptions: [String: Any] = [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ]
            
            centralManager.scanForPeripherals(withServices: nil, options: scanOptions)
            
            // 设置超时，如果在10秒内未找到设备则提示错误
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self else { return }
                
                if self.connectedPeripheral == nil {
                    self.centralManager.stopScan()
                    print("未能找到指定UUID的设备，请确认设备已开启并在范围内")
                    exit(1)
                }
            }
        }
    }
}



// 主程序入口
print("MacBLECtrl - macOS蓝牙设备扫描和电量检测工具")
print("=======================================\n")

// 解析命令行参数
var scanTime = 20
var deviceUUID: String? = nil

let args = CommandLine.arguments
for i in 1..<args.count {
    if args[i] == "-u" || args[i] == "--uuid", i + 1 < args.count {
        deviceUUID = args[i + 1]
    } else if args[i] == "-t" || args[i] == "--time", i + 1 < args.count, let time = Int(args[i + 1]), time > 0 {
        scanTime = time
    } else if args[i] == "-h" || args[i] == "--help" {
        print("使用方法:")
        print("  无参数: 交互式扫描并连接设备")
        print("  -u, --uuid <UUID>: 直接连接到指定UUID的设备并获取电量")
        print("  -t, --time <秒数>: 设置扫描时间（默认20秒）")
        print("  -h, --help: 显示帮助信息")
        exit(0)
    }
}

// 如果没有指定UUID，则使用交互式模式
if deviceUUID == nil {
    print("请输入扫描时间（秒），直接回车使用默认值(\(scanTime)秒):")
    if let input = readLine(), !input.isEmpty, let userTime = Int(input), userTime > 0 {
        scanTime = userTime
        print("将使用 \(scanTime) 秒的扫描时间")
    } else {
        print("使用默认扫描时间: \(scanTime)秒")
    }
}

let manager = LegacyBluetoothManager(scanDuration: scanTime, deviceUUID: deviceUUID)
RunLoop.main.run()
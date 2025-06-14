# 计划：将 MacBLECtrl 集成到 Home Assistant

**目标:**
1.  在 Home Assistant 中创建一个传感器，用于显示发现的蓝牙设备数量和详细列表。
2.  在 Home Assistant 中创建一个服务，用于手动触发蓝牙扫描。

**架构图:**
```mermaid
graph TD
    subgraph Home Assistant
        A[RESTful Sensor: sensor.discovered_bluetooth_devices]
        C[RESTful Command: rest_command.ble_start_scan]
        E[Lovelace UI Button]

        A -- GET /devices (every 60s) --> B
        C -- POST /scan --> B
        E -- calls service --> C
    end

    subgraph Mac (172.17.123.229)
        B(MacBLECtrl API)
    end

    B -- Scans & Connects --> D[Bluetooth Devices]

    style A fill:#f9f,stroke:#333,stroke-width:2px
    style C fill:#ccf,stroke:#333,stroke-width:2px
```

**执行步骤分为两部分：**

---

### 第一部分：修改 `MacBLECtrl` 项目 (Swift 代码)

**目的**: 调整 API 响应格式，以便 Home Assistant 能够轻松解析。

1.  **定义新的响应结构体**
    *   **文件**: `Sources/MacBLECtrl/routes.swift`
    *   **操作**: 在文件顶部，`DeviceInfo` 结构体下面，添加一个新的结构体 `DeviceListResponse`。

    ```swift
    // Add this new struct
    struct DeviceListResponse: Content {
        let devices: [DeviceInfo]
    }
    ```

2.  **修改 `/devices` 端点**
    *   **文件**: `Sources/MacBLECtrl/routes.swift`
    *   **操作**: 修改 `app.get("devices")` 路由，使其返回 `DeviceListResponse` 结构体。

    *   **将**
        ```swift
        app.get("devices") { req -> [DeviceInfo] in
        ```
    *   **修改为**
        ```swift
        app.get("devices") { req -> DeviceListResponse in
        ```
    *   **并且，将**
        ```swift
        return devices.map { ... }
        ```
    *   **修改为**
        ```swift
        let deviceInfos = devices.map { deviceInfo in
            DeviceInfo(
                name: deviceInfo.name,
                identifier: deviceInfo.identifier,
                rssi: deviceInfo.rssi,
                isConnectable: deviceInfo.isConnectable
            )
        }
        return DeviceListResponse(devices: deviceInfos)
        ```

**完成后，需要重新编译并运行 `MacBLECtrl` 项目。**

---

### 第二部分：修改 Home Assistant 配置

**目的**: 添加与 `MacBLECtrl` API 交互的传感器和服务。

1.  **添加 `rest_command`**
    *   **文件**: `configuration.yaml`
    *   **操作**: 在文件的顶层添加以下配置。

    ```yaml
    # Add this section for the manual scan command
    rest_command:
      ble_start_scan:
        url: "http://172.17.123.229:8080/scan"
        method: POST
    ```

2.  **添加 `rest` 传感器**
    *   **文件**: `configuration.yaml`
    *   **操作**: 在 `sensor:` 部分，添加一个新的 `rest` 平台传感器。

    ```yaml
    sensor:
      # ... (your existing sensors) ...

      # Add this new sensor for Bluetooth devices
      - platform: rest
        name: "Discovered Bluetooth Devices"
        resource: "http://172.17.123.229:8080/devices"
        method: GET
        scan_interval: 60
        value_template: "{{ value_json.devices | length }}"
        unit_of_measurement: "devices"
        json_attributes:
          - "devices"
    ```

**完成后，需要检查配置并重启 Home Assistant。**
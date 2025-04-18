# MacBLECtrl

一个macOS命令行工具，用于搜索附近的蓝牙设备并获取它们的电量信息。

## 功能

- 扫描并显示附近的蓝牙设备
- 连接到支持的设备并读取电量信息
- 显示设备名称、MAC地址和电量百分比

## 使用方法

```bash
# 编译项目
swift build

# 运行程序
./.build/debug/MacBLECtrl
```

## 系统要求

- macOS 10.15+
- Swift 5.0+

## 注意事项

- 并非所有蓝牙设备都支持电量信息读取
- 设备需要实现标准的电池服务(Battery Service)才能读取电量
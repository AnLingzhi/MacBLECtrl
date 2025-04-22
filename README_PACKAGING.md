# MacBLECtrl 打包指南

本文档提供了将 MacBLECtrl 打包为可在后台运行的 macOS 应用程序的详细说明。

## 应用程序特性

- **后台运行**：应用程序配置为 Agent 应用，在后台运行而不显示 Dock 图标
- **系统启动时自动运行**：通过 LaunchAgent 配置，应用程序可以在系统启动时自动运行
- **蓝牙功能**：保留了所有蓝牙扫描和控制功能
- **Web 服务器**：保留了 Vapor Web 服务器功能，可通过 HTTP 接口控制

## 打包步骤

### 1. 使用提供的构建脚本

我们提供了一个自动化构建脚本，可以将应用程序打包为 macOS `.app` 格式：

```bash
# 确保脚本有执行权限
chmod +x build_app.sh

# 运行构建脚本
./build_app.sh
```

脚本将：
- 编译应用程序的发布版本
- 创建正确的 `.app` 目录结构
- 复制所有必要的文件
- 生成安装说明

### 2. 手动安装

构建完成后，按照以下步骤安装应用程序：

1. 将生成的 `MacBLECtrl.app` 复制到 `/Applications` 目录：
   ```bash
   cp -r MacBLECtrl.app /Applications/
   ```

2. 安装 LaunchAgent 以启用后台自动启动：
   ```bash
   mkdir -p ~/Library/LaunchAgents
   cp MacBLECtrl.app/Contents/Resources/com.example.MacBLECtrl.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.example.MacBLECtrl.plist
   ```

### 3. 验证安装

安装完成后，应用程序将立即在后台启动。您可以通过以下方式验证应用程序是否正在运行：

```bash
# 检查进程是否运行
ps aux | grep MacBLECtrl

# 检查 Web 服务器是否响应
curl http://localhost:8080
```

## 自定义配置

如果需要自定义应用程序，可以修改以下文件：

- `Sources/MacBLECtrl/Info.plist`：应用程序配置，包括标识符和权限
- `Resources/com.example.MacBLECtrl.plist`：LaunchAgent 配置，控制启动行为

## 故障排除

如果应用程序未能正确启动，请检查以下日志文件：

```bash
cat /tmp/MacBLECtrl.err
cat /tmp/MacBLECtrl.out
```

## 卸载

要卸载应用程序，请执行以下步骤：

```bash
# 卸载 LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.example.MacBLECtrl.plist
rm ~/Library/LaunchAgents/com.example.MacBLECtrl.plist

# 删除应用程序
rm -rf /Applications/MacBLECtrl.app
```
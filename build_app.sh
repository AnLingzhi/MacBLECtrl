#!/bin/bash

# 构建脚本：将MacBLECtrl打包为macOS应用程序

echo "开始构建MacBLECtrl.app..."

# 设置变量
APP_NAME="MacBLECtrl"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 清理旧的构建
if [ -d "$APP_DIR" ]; then
  echo "删除旧的应用程序..."
  rm -rf "$APP_DIR"
fi

# 创建应用程序目录结构
echo "创建应用程序目录结构..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 构建应用程序
echo "编译应用程序..."
swift build -c release

# 复制可执行文件
echo "复制可执行文件到应用程序包..."
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# 复制Info.plist
echo "复制Info.plist..."
cp "Sources/$APP_NAME/Info.plist" "$CONTENTS_DIR/"

# 复制LaunchAgent配置
echo "复制LaunchAgent配置..."
cp "Resources/com.example.MacBLECtrl.plist" "$RESOURCES_DIR/"

# 创建PkgInfo文件
echo "创建PkgInfo文件..."
echo "APPLE" > "$CONTENTS_DIR/PkgInfo"

echo "应用程序构建完成: $(pwd)/$APP_DIR"
echo ""
echo "安装说明:"
echo "1. 将 $APP_DIR 复制到 /Applications 目录"
echo "2. 安装LaunchAgent以启用后台自动启动:"
echo "   mkdir -p ~/Library/LaunchAgents"
echo "   cp $RESOURCES_DIR/com.example.MacBLECtrl.plist ~/Library/LaunchAgents/"
echo "   launchctl load ~/Library/LaunchAgents/com.example.MacBLECtrl.plist"
echo ""
echo "完成！应用程序将在后台运行，并在系统启动时自动启动。"
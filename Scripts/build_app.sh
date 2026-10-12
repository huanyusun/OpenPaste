#!/bin/zsh
# OpenPaste 打包脚本：把 swift build 产物组装成可分发的 OpenPaste.app
set -e

PROJECT_DIR="/Users/sunhuanyu/WorkBuddy/paste/OpenPaste"
APP_NAME="OpenPaste"
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_DIR="${PROJECT_DIR}/dist/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

cd "$PROJECT_DIR"
# --disable-sandbox：本机环境 sandbox-exec 受限，不加会报 sandbox_apply: Operation not permitted
swift build -c release --package-path "$PROJECT_DIR" --disable-sandbox

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "$CONTENTS/MacOS/"

cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>OpenPaste</string>
    <key>CFBundleIdentifier</key>
    <string>io.openpaste.app</string>
    <key>CFBundleName</key>
    <string>OpenPaste</string>
    <key>CFBundleDisplayName</key>
    <string>OpenPaste</string>
    <key>CFBundleVersion</key>
    <string>0.3.1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>io.openpaste.app</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>openpaste</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>OpenPaste 需要辅助功能权限，以便将剪贴板内容直接粘贴到你正在使用的应用光标处。</string>
</dict>
</plist>
EOF

# Ad-hoc 签名（本地运行够用；分发需要 Developer ID）
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "[warn] 签名跳过"

echo "✅ 打包完成: ${APP_DIR}"
echo "首次运行前请到 系统设置 → 隐私与安全性 → 辅助功能 授予权限（否则只能复制回剪贴板，不能直接粘贴）。"

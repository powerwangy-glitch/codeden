#!/bin/bash
# 把 SwiftPM 可执行打包成可日常使用的 NotchIsland.app
set -e
cd "$(dirname "$0")"

echo "▶ 编译 release…"
swift build -c release

APP="dist/NotchIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bridge"

cp ".build/release/NotchIsland" "$APP/Contents/MacOS/NotchIsland"
cp bridge/notch-bridge.py \
   bridge/install.py \
   bridge/uninstall.py \
   bridge/notch-statusline.py \
   bridge/notch-codex-notify.py \
   "$APP/Contents/Resources/bridge/"
chmod +x "$APP/Contents/Resources/bridge/"*.py

# 图标：没有就现生成
if [ ! -f icon/AppIcon.icns ]; then
  swift tools/make-icon.swift && iconutil -c icns icon/AppIcon.iconset -o icon/AppIcon.icns
fi
cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>码岛</string>
  <key>CFBundleDisplayName</key>     <string>码岛</string>
  <key>CFBundleIdentifier</key>      <string>app.codeden.macos</string>
  <key>CFBundleExecutable</key>      <string>NotchIsland</string>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>0.1.1</string>
  <key>CFBundleVersion</key>         <string>2</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSUIElement</key>             <true/>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# ad-hoc 签名（让登录项 / TCC 稳定）
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "（codesign 跳过）"

echo "✅ 已生成 $APP"
echo "   运行：open \"$APP\""
echo "   建议拖到 /Applications 后再开机自启更稳。"

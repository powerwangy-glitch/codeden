#!/bin/bash
# 把 NotchIsland.app 做成「可直接分发」的公证 DMG（Vibe Island 同款路径）。
# 你需要先具备（都在你本人的 Apple Developer 账号下完成，本脚本不接触任何密码）：
#   1) 一个 "Developer ID Application" 证书已装进登录钥匙串
#        （Xcode → Settings → Accounts → Manage Certificates → + Developer ID Application）
#   2) 一个用于 notarytool 的钥匙串配置（一次性创建）：
#        xcrun notarytool store-credentials NotchNotary \
#          --apple-id "你的AppleID" --team-id "你的TeamID" --password "App专用密码"
#      （App 专用密码在 appleid.apple.com → 登录与安全 → App 专用密码 生成）
#
# 然后设置两个环境变量后运行本脚本：
#   DEV_ID="Developer ID Application: 你的名字 (TEAMID)" KEYCHAIN_PROFILE=NotchNotary ./dist-notarize.sh
set -e
cd "$(dirname "$0")"

: "${DEV_ID:?请设置 DEV_ID（你的 Developer ID Application 证书全名）}"
: "${KEYCHAIN_PROFILE:?请设置 KEYCHAIN_PROFILE（notarytool store-credentials 的名字）}"

APP="dist/NotchIsland.app"
DMG="dist/NotchIsland.dmg"

echo "▶ 重新构建 .app…"; ./build-app.sh >/dev/null

echo "▶ 用 Developer ID 签名（含 hardened runtime）…"
codesign --force --deep --options runtime --timestamp \
  --sign "$DEV_ID" "$APP"

echo "▶ 打 DMG…"
rm -f "$DMG"
hdiutil create -volname "NotchIsland" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "▶ 提交公证（等苹果返回，可能几分钟）…"
xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "▶ 装订公证票据…"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

echo "✅ 完成：$DMG —— 任何 Mac 双击即可安装运行（已过 Gatekeeper）。"

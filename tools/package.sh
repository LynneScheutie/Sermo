#!/bin/bash
# 打包 Sermo：编译 → 组装 .app → 自检 → 临时签名 → 可选安装到 /Applications
#
# 用法：
#   ./tools/package.sh            产出 dist/Sermo.app
#   ./tools/package.sh --install  额外覆盖安装到 /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Sermo.app"
PLIST="$ROOT/tools/Info.plist"
RES="$ROOT/Resources"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

echo "==> 1/5 编译　版本 ${VERSION}（arm64 + x86_64 通用二进制）"
mkdir -p "$ROOT/build"
MIN_MACOS=14.0
for ARCH in arm64 x86_64; do
    swiftc -O -parse-as-library -swift-version 6 \
        -target "${ARCH}-apple-macos${MIN_MACOS}" \
        -o "$ROOT/build/Sermo-$ARCH" \
        $(find "$ROOT/Sources" -name '*.swift') \
        -framework WebKit
done
# 合成一个可执行文件，Apple 芯片与 Intel 都跑同一份安装包
lipo -create -output "$ROOT/build/Sermo" \
    "$ROOT/build/Sermo-arm64" "$ROOT/build/Sermo-x86_64"
printf '  架构: %s\n' "$(lipo -archs "$ROOT/build/Sermo")"

echo "==> 2/5 组装 App"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/build/Sermo" "$APP/Contents/MacOS/Sermo"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$RES/AppIcon.icns" "$APP/Contents/Resources/"
cp "$RES/aether_presets.json" "$APP/Contents/Resources/"

echo "==> 3/5 自检：预设数据是否随包"
for f in AppIcon.icns aether_presets.json; do
    [ -f "$APP/Contents/Resources/$f" ] || { echo "  ✗ 缺 $f"; exit 1; }
    printf '  %-22s %8s 字节\n' "$f" "$(stat -f%z "$APP/Contents/Resources/$f")"
done
python3 -c "import json,sys; json.load(open('$APP/Contents/Resources/aether_presets.json')); print('  aether_presets.json  可解析')"

echo "==> 4/5 临时签名（ad-hoc）"
codesign --force --deep --sign - "$APP" 2>&1 | sed 's/^/  /' || true
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" | sed 's/^/  /' || true

echo "==> 5/5 安装"
if [ "$INSTALL" = "1" ]; then
    rm -rf "/Applications/Sermo.app"
    cp -R "$APP" "/Applications/Sermo.app"
    echo "  已安装到 /Applications/Sermo.app"
else
    echo "  跳过（加 --install 可安装）"
fi

du -sh "$APP"
echo "完成。"

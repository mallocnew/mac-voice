#!/usr/bin/env bash
# 打包 MiniVoice：Release 通用二进制 .app → DMG（可选 ZIP）
#
# 用法：
#   ./scripts/package-dmg.sh
#   ./scripts/package-dmg.sh --zip          # 额外打 zip
#   ./scripts/package-dmg.sh --keep-build   # 保留中间编译产物
#
# 前置：
#   1. 已安装完整 Xcode（不只是 Command Line Tools）
#   2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#   3. 在 Xcode 里给 Target 选好 Signing Team（至少本地签名）

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/MacVoice.xcodeproj"
SCHEME="MacVoice"
APP_NAME="MiniVoice"
DISPLAY_NAME="MiniVoice"
BUNDLE_ID="com.bat.minivoice"
DIST="$ROOT/dist"
DERIVED="$DIST/DerivedData"
EXPORT_DIR="$DIST/export"
STAGE="$DIST/dmg-stage"
# DMG/ZIP 路径在读出版本号后确定
DMG_PATH=""
ZIP_PATH=""

MAKE_ZIP=0
KEEP_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --zip) MAKE_ZIP=1 ;;
    --keep-build) KEEP_BUILD=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $arg"
      echo "支持: --zip  --keep-build  --help"
      exit 1
      ;;
  esac
done

log()  { printf '\n==> %s\n' "$*"; }
fail() { printf '错误：%s\n' "$*" >&2; exit 1; }

# --- 环境检查 -------------------------------------------------------------

if [[ ! -d "/Applications/Xcode.app" ]]; then
  fail "未找到 /Applications/Xcode.app。请先从 App Store 安装完整 Xcode。"
fi

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEVELOPER_DIR" != *"/Xcode.app/Contents/Developer" ]]; then
  fail "当前开发者目录是：$DEVELOPER_DIR
请执行：
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
然后再运行本脚本。"
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  fail "xcodebuild 不可用。请打开一次 Xcode 并完成首次许可/组件安装。"
fi

log "Xcode 版本"
xcodebuild -version

# --- 清理 / 准备 ----------------------------------------------------------

log "准备输出目录 $DIST"
rm -rf "$DIST"
mkdir -p "$DERIVED" "$EXPORT_DIR"

# --- 编译 -----------------------------------------------------------------

log "编译 Release（arm64 + x86_64）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=NO \
  build

APP_SRC="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name "${APP_NAME}.app" -type d | head -n 1 || true)"
[[ -n "$APP_SRC" && -d "$APP_SRC" ]] || fail "未找到编译产物 ${APP_NAME}.app
请先在 Xcode 中用 Release 手动编译一次，确认 Signing 无报错。"

APP_DST="$EXPORT_DIR/${APP_NAME}.app"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

BINARY="$APP_DST/Contents/MacOS/${APP_NAME}"
[[ -f "$BINARY" ]] || fail "App 内缺少可执行文件：$BINARY"

log "架构信息"
if command -v lipo >/dev/null 2>&1; then
  lipo -info "$BINARY" || true
fi

log "代码签名信息"
codesign -dv --verbose=2 "$APP_DST" 2>&1 | sed -n '1,20p' || true

# 版本号（来自 Xcode MARKETING_VERSION / CURRENT_PROJECT_VERSION）
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DST/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DST/Contents/Info.plist" 2>/dev/null || echo "1")"
ARTIFACT="${APP_NAME}-${VERSION}"
DMG_PATH="$DIST/${ARTIFACT}.dmg"
ZIP_PATH="$DIST/${ARTIFACT}.zip"
log "版本 $VERSION (build $BUILD)  Bundle ID: $BUNDLE_ID"

# --- DMG ------------------------------------------------------------------

log "制作 DMG → $(basename "$DMG_PATH")"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_DST" "$STAGE/${APP_NAME}.app"
ln -sf /Applications "$STAGE/Applications"

TMP_DMG="$DIST/${APP_NAME}-temp.dmg"
rm -f "$TMP_DMG" "$DMG_PATH"

# 先做可读写镜像，再转成压缩只读（UDZO 兼容性最好）
hdiutil create \
  -volname "${DISPLAY_NAME} ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "$TMP_DMG" >/dev/null

hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

rm -f "$TMP_DMG"
rm -rf "$STAGE"

# 额外提供不带版本号的稳定文件名，方便脚本/文档引用
ln -sf "$(basename "$DMG_PATH")" "$DIST/${APP_NAME}.dmg"

# --- 可选 ZIP -------------------------------------------------------------

if [[ "$MAKE_ZIP" -eq 1 ]]; then
  log "制作 ZIP → $(basename "$ZIP_PATH")"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DST" "$ZIP_PATH"
  ln -sf "$(basename "$ZIP_PATH")" "$DIST/${APP_NAME}.zip"
fi

# --- 清理中间产物 ---------------------------------------------------------

if [[ "$KEEP_BUILD" -eq 0 ]]; then
  log "清理 DerivedData"
  rm -rf "$DERIVED"
fi

# --- 完成 -----------------------------------------------------------------

BYTES="$(stat -f%z "$DMG_PATH" 2>/dev/null || echo 0)"
SIZE_MB="$(awk -v b="$BYTES" 'BEGIN { printf "%.1f" , b/1024/1024 }')"

cat <<EOF

打包完成
--------
版本 : ${VERSION} (build ${BUILD})
App  : $APP_DST
DMG  : $DMG_PATH  (${SIZE_MB} MB)
EOF

if [[ "$MAKE_ZIP" -eq 1 ]]; then
  echo "ZIP  : $ZIP_PATH"
fi

cat <<EOF

使用方式：
  双击 DMG → 把「${APP_NAME}」拖到 Applications

注意：
  • 本包为本地/Automatic 签名，其他 Mac 首次打开可能需：
    右键 App → 打开，或在「隐私与安全性」里仍允许打开
  • 若要无提示分发，需加入 Apple Developer Program，
    使用 Developer ID 签名并 notarize（公证）
  • 改版本号：Xcode → Target → General → Version / Build
    （对应 MARKETING_VERSION / CURRENT_PROJECT_VERSION）
EOF

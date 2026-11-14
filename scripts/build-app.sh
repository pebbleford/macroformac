#!/usr/bin/env bash
# Builds MacroForMac.app into ./dist.
#
#   ./scripts/build-app.sh               # release build for this Mac's architecture
#   UNIVERSAL=1 ./scripts/build-app.sh   # Apple Silicon + Intel (needs full Xcode)
#   SIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacroForMac"
CONFIG="${CONFIG:-release}"
OUT_DIR="${OUT_DIR:-dist}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc signature

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building $APP_NAME ($CONFIG ${ARCH_FLAGS[*]:-native})"
swift build -c "$CONFIG" --product "$APP_NAME" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" --product "$APP_NAME" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$OUT_DIR/$APP_NAME.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Support/Info.plist > "$APP/Contents/Info.plist"
if [[ -f Support/AppIcon.icns ]]; then
  cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (identity: $SIGN_IDENTITY)"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"

echo "==> Done: $APP"

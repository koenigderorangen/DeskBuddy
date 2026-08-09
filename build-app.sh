#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
OUTPUT_ROOT="$PROJECT_DIR/outputs"
APP_DIR="$OUTPUT_ROOT/DeskBuddy.app"
VERSION_FILE="$PROJECT_DIR/VERSION"
APP_VERSION="${DESKBUDDY_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${DESKBUDDY_BUILD_NUMBER:-1}"

if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Invalid DeskBuddy version: $APP_VERSION" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
  echo "Invalid build number: $BUILD_NUMBER" >&2
  exit 1
fi
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache"

cd "$PROJECT_DIR"
swift build --disable-sandbox -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/DeskBuddy" "$APP_DIR/Contents/MacOS/DeskBuddy"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
xcrun actool "Resources/Assets.xcassets" \
  --compile "$APP_DIR/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$PROJECT_DIR/.build/asset-info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"

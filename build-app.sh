#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
OUTPUT_ROOT="$PROJECT_DIR/outputs"
APP_DIR="$OUTPUT_ROOT/DeskBuddy.app"
VERSION_FILE="$PROJECT_DIR/VERSION"
APP_VERSION="${DESKBUDDY_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${DESKBUDDY_BUILD_NUMBER:-1}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
BUILD_CONFIGURATION="release"

if (( $# > 1 )); then
  echo "Usage: ./build-app.sh [--debug|--release]" >&2
  exit 1
fi

case "${1:-}" in
  "") ;;
  --debug) BUILD_CONFIGURATION="debug" ;;
  --release) ;;
  *)
    echo "Usage: ./build-app.sh [--debug|--release]" >&2
    exit 1
    ;;
esac

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
swift build --disable-sandbox -c "$BUILD_CONFIGURATION"

SPARKLE_FRAMEWORK="$(find "$PROJECT_DIR/.build/artifacts" -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -type d -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "Sparkle.framework was not found in SwiftPM build artifacts." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp ".build/$BUILD_CONFIGURATION/DeskBuddy" "$APP_DIR/Contents/MacOS/DeskBuddy"
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP_DIR/Contents/Info.plist"
fi
xcrun actool "Resources/Assets.xcassets" \
  --compile "$APP_DIR/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$PROJECT_DIR/.build/asset-info.plist"

codesign --force --deep --sign - "$APP_DIR"
otool -l "$APP_DIR/Contents/MacOS/DeskBuddy" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'
codesign --deep --strict --verify "$APP_DIR"
echo "Built DeskBuddy.app in $BUILD_CONFIGURATION mode"
echo "$APP_DIR"

#!/bin/bash
set -e

EXE_NAME="backtick-plus-plus-helper"
APP_NAME="Backtick++ Helper"
APP_BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"
EXECUTABLE="$BUILD_DIR/$EXE_NAME"
BUNDLE_DIR="$APP_BUNDLE/Contents/MacOS"
PLIST_DIR="$APP_BUNDLE/Contents"
PLIST_FILE="Info.plist"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
ICON_PNG="../icon.png"  # Set your PNG icon path here
ICONSET_DIR="icon.iconset"
ICNS_FILE="icon.icns"

# Build the release executable
swift build -c release

# Remove old bundle if exists
rm -rf "$APP_BUNDLE"
rm -rf "$ICONSET_DIR" "$ICNS_FILE"

# Create bundle structure
mkdir -p "$BUNDLE_DIR"

# Copy executable
cp "$EXECUTABLE" "$BUNDLE_DIR/"

# Copy Info.plist (must exist in swift-helper/)
if [ -f "$PLIST_FILE" ]; then
  mkdir -p "$PLIST_DIR"
  cp "$PLIST_FILE" "$PLIST_DIR/"
else
  echo "Warning: $PLIST_FILE not found. Bundle will be missing Info.plist."
fi

# Convert PNG to ICNS and copy to Resources
if [ -f "$ICON_PNG" ]; then
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png"
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png"
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png"
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png"
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png"
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png"
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png"
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
  mkdir -p "$RESOURCES_DIR"
  cp "$ICNS_FILE" "$RESOURCES_DIR/"
else
  echo "Warning: $ICON_PNG not found. Bundle will be missing icon."
fi

echo "Created $APP_BUNDLE"

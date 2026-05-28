#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ParquetPeek"
BUNDLE_ID="dev.codex.ParquetPeek"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
STAGE_DIR="$RELEASE_DIR/stage"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Assets/AppIcon.icns"
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"

if [ -x /opt/homebrew/opt/llvm/bin/clang++ ]; then
  export CC="/opt/homebrew/opt/llvm/bin/clang"
  export CXX="/opt/homebrew/opt/llvm/bin/clang++"
fi

export DYLD_LIBRARY_PATH="/opt/homebrew/lib:/opt/homebrew/opt/apache-arrow/lib:/usr/local/lib:/usr/local/opt/apache-arrow/lib:${DYLD_LIBRARY_PATH:-}"

cd "$ROOT_DIR"
swift build -c release

BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$RELEASE_DIR"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

is_bundled_dep() {
  case "$1" in
    /opt/homebrew/*|/usr/local/*|@rpath/*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_dependency_path() {
  local dep="$1"
  if [ -f "$dep" ]; then
    printf '%s\n' "$dep"
    return 0
  fi
  local dep_name
  dep_name="$(basename "$dep")"
  for dir in \
    /opt/homebrew/lib \
    /opt/homebrew/opt/apache-arrow/lib \
    /opt/homebrew/opt/aws-sdk-cpp/lib \
    /opt/homebrew/opt/aws-crt-cpp/lib \
    /opt/homebrew/opt/aws-c-common/lib \
    /opt/homebrew/opt/aws-c-cal/lib \
    /opt/homebrew/opt/aws-c-compression/lib \
    /opt/homebrew/opt/aws-c-event-stream/lib \
    /opt/homebrew/opt/aws-c-http/lib \
    /opt/homebrew/opt/aws-c-io/lib \
    /opt/homebrew/opt/aws-c-mqtt/lib \
    /opt/homebrew/opt/aws-c-s3/lib \
    /opt/homebrew/opt/aws-c-auth/lib \
    /opt/homebrew/opt/aws-c-sdkutils/lib \
    /opt/homebrew/opt/aws-checksums/lib \
    /opt/homebrew/opt/brotli/lib \
    /opt/homebrew/opt/lz4/lib \
    /opt/homebrew/opt/openssl@3/lib \
    /opt/homebrew/opt/snappy/lib \
    /opt/homebrew/opt/thrift/lib \
    /opt/homebrew/opt/zstd/lib \
    /usr/local/lib; do
    if [ -f "$dir/$dep_name" ]; then
      printf '%s\n' "$dir/$dep_name"
      return 0
    fi
  done
  return 1
}

copy_dependency_tree() {
  local binary="$1"
  local changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    while IFS= read -r dep; do
      if ! is_bundled_dep "$dep"; then
        continue
      fi
      local resolved_dep
      if ! resolved_dep="$(resolve_dependency_path "$dep")"; then
        continue
      fi
      local dep_name
      dep_name="$(basename "$resolved_dep")"
      if [ ! -f "$APP_FRAMEWORKS/$dep_name" ]; then
        cp "$resolved_dep" "$APP_FRAMEWORKS/$dep_name"
        chmod u+w "$APP_FRAMEWORKS/$dep_name"
        changed=1
      fi
    done < <(find "$APP_BINARY" "$APP_FRAMEWORKS" -type f -print0 | xargs -0 otool -L 2>/dev/null | awk 'index($1, "/") == 1 || index($1, "@rpath/") == 1 { print $1 }' | sort -u)
  done
}

rewrite_load_commands() {
  local target="$1"
  local target_name
  target_name="$(basename "$target")"
  if [ "$target" != "$APP_BINARY" ]; then
    install_name_tool -id "@rpath/$target_name" "$target" 2>/dev/null || true
  fi
  while IFS= read -r dep; do
    if is_bundled_dep "$dep"; then
      install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$target" 2>/dev/null || true
    fi
  done < <(otool -L "$target" | awk '$1 ~ /^\// { print $1 }')
}

copy_dependency_tree "$APP_BINARY"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true

while IFS= read -r binary; do
  rewrite_load_commands "$binary"
done < <(find "$APP_BINARY" "$APP_FRAMEWORKS" -type f)

codesign --force --deep --sign - "$APP_BUNDLE"

ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"

codesign --verify --deep --strict "$APP_BUNDLE"
spctl --assess --type execute "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Packaged app: $APP_BUNDLE"
echo "Installer DMG: $DMG_PATH"

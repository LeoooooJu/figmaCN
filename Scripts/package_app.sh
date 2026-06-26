#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FigmaCN Studio Swift"
APP_DIR="$ROOT_DIR/release/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="FigmaCNStudioSwift"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES/Runtime/lang"

cp ".build/release/$EXECUTABLE" "$MACOS/$EXECUTABLE"
chmod +x "$MACOS/$EXECUTABLE"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>cn.FigmaCN.studio.swift</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticTermination</key>
  <false/>
  <key>NSSupportsSuddenTermination</key>
  <false/>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/Runtime/injector.py" "$RESOURCES/Runtime/injector.py"
cp "$ROOT_DIR/Runtime/validate_lang.py" "$RESOURCES/Runtime/validate_lang.py"
cp "$ROOT_DIR/Runtime/start_proxy.sh" "$RESOURCES/Runtime/start_proxy.sh"
cp "$ROOT_DIR/Runtime/README.md" "$RESOURCES/Runtime/README.md"
cp "$ROOT_DIR/Runtime/lang/"*.json "$RESOURCES/Runtime/lang/"

MITMPROXY_APP=""
if command -v mitmdump >/dev/null 2>&1; then
  MITMDUMP_PATH="$(python3 - <<'PY'
import os, shutil
path = shutil.which("mitmdump") or ""
print(os.path.realpath(path) if path else "")
PY
)"
  case "$MITMDUMP_PATH" in
    */mitmproxy.app/Contents/MacOS/mitmdump)
      MITMPROXY_APP="${MITMDUMP_PATH%/Contents/MacOS/mitmdump}"
      ;;
  esac
fi

if [[ -z "$MITMPROXY_APP" ]] && command -v brew >/dev/null 2>&1; then
  CASKROOM="$(brew --caskroom mitmproxy 2>/dev/null || true)"
  if [[ -n "$CASKROOM" ]]; then
    MITMPROXY_APP="$(find "$CASKROOM" -path '*/mitmproxy.app' -maxdepth 3 -type d 2>/dev/null | sort -V | tail -1)"
  fi
fi

if [[ -z "$MITMPROXY_APP" || ! -x "$MITMPROXY_APP/Contents/MacOS/mitmdump" ]]; then
  echo "未找到可内置的 mitmproxy.app，请先安装：brew install --cask mitmproxy" >&2
  exit 1
fi

mkdir -p "$RESOURCES/mitmproxy"
ditto "$MITMPROXY_APP" "$RESOURCES/mitmproxy/mitmproxy.app"

xattr -cr "$APP_DIR" 2>/dev/null || true

du -sh "$APP_DIR"
echo "$APP_DIR"

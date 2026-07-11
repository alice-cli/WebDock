#!/bin/bash
# Build WebDock.app and sign with a stable identity so TCC permissions survive rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

APP="WebDock.app"
BIN_DIR="$APP/Contents/MacOS"
EXE="$BIN_DIR/WebDock"

KC_PATH="${WEBDOCK_KEYCHAIN:-$HOME/Library/Keychains/WebDock.keychain-db}"
KC_PASS_FILE="${WEBDOCK_KEYCHAIN_PASS_FILE:-$HOME/Library/Application Support/WebDock/.sign-pass}"
KC_PASS_DEFAULT="webdock-sign"
HASH_FILE="${WEBDOCK_IDENTITY_HASH_FILE:-$HOME/Library/Application Support/WebDock/.sign-hash}"

echo "compiling via SPM…"
swift build -c release

# Brand icons from MacRemote.png (app Dock icon + web favicon)
ICON_SRC="MacRemote.png"
ASSETS_DIR="Assets"
if [[ -f "${ICON_SRC}" ]]; then
  echo "icons from ${ICON_SRC} ..."
  mkdir -p "${ASSETS_DIR}/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z "${s}" "${s}" "${ICON_SRC}" --out "${ASSETS_DIR}/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    s2=$((s * 2))
    sips -z "${s2}" "${s2}" "${ICON_SRC}" --out "${ASSETS_DIR}/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "${ASSETS_DIR}/AppIcon.iconset" -o "${ASSETS_DIR}/AppIcon.icns"
  sips -z 32 32 "${ICON_SRC}" --out "${ASSETS_DIR}/favicon.png" >/dev/null
  sips -z 32 32 "${ICON_SRC}" --out "${ASSETS_DIR}/favicon-32.png" >/dev/null
  sips -z 180 180 "${ICON_SRC}" --out "${ASSETS_DIR}/apple-touch-icon.png" >/dev/null
  sips -z 192 192 "${ICON_SRC}" --out "${ASSETS_DIR}/favicon-192.png" >/dev/null
fi

rm -rf "${APP}"
mkdir -p "${BIN_DIR}" "${APP}/Contents/Resources"
cp ".build/release/WebDock" "${EXE}"
chmod +x "${EXE}"

# Copy brand assets into the app bundle
if [[ -f "${ASSETS_DIR}/AppIcon.icns" ]]; then
  cp "${ASSETS_DIR}/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi
for f in favicon.png favicon-32.png apple-touch-icon.png favicon-192.png; do
  if [[ -f "${ASSETS_DIR}/${f}" ]]; then
    cp "${ASSETS_DIR}/${f}" "${APP}/Contents/Resources/${f}"
  fi
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>WebDock</string>
    <key>CFBundleDisplayName</key><string>WebDock</string>
    <key>CFBundleIdentifier</key><string>com.poc.webdock</string>
    <key>CFBundleExecutable</key><string>WebDock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><false/>
    <key>LSBackgroundOnly</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSScreenCaptureUsageDescription</key><string>Capture app windows to serve them over the web.</string>
    <key>NSAppleEventsUsageDescription</key><string>Open new Terminal windows and control apps for remote desktop.</string>
</dict>
</plist>
PLIST

resolve_pass() {
  if [[ -f "$KC_PASS_FILE" ]]; then
    cat "$KC_PASS_FILE"
  else
    echo "$KC_PASS_DEFAULT"
  fi
}

# Prefer SHA-1 of cert in WebDock keychain (avoids "ambiguous identity" with login keychain).
resolve_identity() {
  local hash=""
  if [[ -f "$HASH_FILE" ]]; then
    hash=$(tr -d ' \n' < "$HASH_FILE")
  fi
  if [[ -z "$hash" && -f "$KC_PATH" ]]; then
    hash=$(security find-certificate -c "WebDock Dev" -Z "$KC_PATH" 2>/dev/null \
      | awk '/SHA-1 hash:/{print $3; exit}')
  fi
  if [[ -z "$hash" && -f "$KC_PATH" ]]; then
    hash=$(security find-identity -v -p codesigning "$KC_PATH" 2>/dev/null \
      | awk '/WebDock Dev/{print $2; exit}')
  fi
  echo "$hash"
}

sign_stable() {
  if [[ ! -f "$KC_PATH" ]]; then
    echo "no keychain at $KC_PATH"
    return 1
  fi
  local pass id
  pass=$(resolve_pass)
  security unlock-keychain -p "$pass" "$KC_PATH" 2>/dev/null || {
    echo "unlock failed"
    return 1
  }
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$pass" "$KC_PATH" >/dev/null 2>&1 || true

  id=$(resolve_identity)
  if [[ -z "$id" ]]; then
    id="WebDock Dev"
  else
    # Cache for next build
    mkdir -p "$(dirname "$HASH_FILE")"
    echo "$id" > "$HASH_FILE"
    chmod 600 "$HASH_FILE" 2>/dev/null || true
  fi

  # Sign by hash + explicit keychain → no SecurityAgent hang, no ambiguous match.
  codesign --force --sign "$id" --keychain "$KC_PATH" --timestamp=none "$APP"
}

# CI / release_notarize: SKIP_SIGN=1 이면 서명 생략 (나중에 Developer ID 로 서명)
if [[ "${SKIP_SIGN:-0}" == "1" ]]; then
  echo "signing skipped (SKIP_SIGN=1)"
else
  echo "signing…"
  if sign_stable; then
    if codesign -d -r- "$APP" 2>&1 | grep -q 'certificate root'; then
      echo "signed stable (certificate-based designated requirement) ✓"
    else
      echo "signed (check: codesign -dv $APP)"
    fi
  else
    echo "WARNING: stable keychain missing — run ./setup_dev_cert.sh"
    echo "  Falling back to ad-hoc (permissions reset every build)."
    codesign --force --sign - "$APP"
  fi
  codesign -dv "$APP" 2>&1 | grep -E 'Authority|Signature|flags|Identifier' || true
fi
echo "built: $APP"

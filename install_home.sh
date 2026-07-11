#!/bin/bash
# Build with STABLE signature and install ONLY to /Users/alice/WebDock.app
# Always kill the old process first so you never run a stale binary.
set -euo pipefail
cd "$(dirname "$0")"

DEST="${WEBDOCK_INSTALL_PATH:-$HOME/WebDock.app}"

echo "==> quit running WebDock"
pkill -x WebDock 2>/dev/null || true
sleep 0.4

echo "==> build + sign"
./build_app.sh

# Prefer stable local cert (setup_dev_cert.sh) so Screen Recording sticks across rebuilds.
# Ad-hoc is OK for one-off open-source installs; macOS may re-prompt permissions on each rebuild.
if codesign -dv WebDock.app 2>&1 | grep -q 'Signature=adhoc'; then
  echo "NOTE: ad-hoc signature (no local WebDock Dev cert)."
  echo "  Optional (recommended if you rebuild often):"
  echo "    ./setup_dev_cert.sh && ./install_home.sh"
  echo "  Apple Developer Program is NOT required."
elif ! codesign -d -r- WebDock.app 2>&1 | grep -q 'certificate root'; then
  echo "NOTE: signature has no certificate designated requirement."
  echo "  Optional: ./setup_dev_cert.sh && ./install_home.sh"
fi

echo "==> install $DEST"
# Replace in place (same path keeps Settings row stable)
rm -rf "$DEST"
ditto WebDock.app "$DEST"
chmod +x "$DEST/Contents/MacOS/WebDock"

echo "==> signature at install path"
codesign -dv "$DEST" 2>&1 | grep -E 'Authority|Signature|Identifier' || true
codesign -d -r- "$DEST" 2>&1 | grep designated || true

echo "==> launch"
open "$DEST"
echo "done."
echo ""
echo "If Screen Recording / Accessibility are OFF, enable the row for:"
echo "  WebDock  (com.poc.webdock)"
echo "Remove duplicate/old WebDock rows in System Settings if you see several."

#!/bin/bash
# Build → Developer ID 서명 → 공증(notarytool) → 스테이플
# 비밀 정보는 저장소에 넣지 말고 notary.env 로 주입하세요.
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE="${NOTARY_ENV:-$HOME/private/apple-certs/notary.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${APPLE_API_KEY_PATH:?APPLE_API_KEY_PATH 없음 — notary.env 확인}"
: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID 없음}"
: "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID 없음 — App Store Connect 통합 화면의 발급자 ID}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: jaehoon oh (ABSDM8J4UQ)}"
APP="WebDock.app"
ZIP="WebDock-notarize.zip"
DIST_DIR="dist"

if [[ ! -f "$APPLE_API_KEY_PATH" ]]; then
  echo "API 키 파일 없음: $APPLE_API_KEY_PATH"
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "Developer ID Application 인증서가 키체인에 없습니다."
  exit 1
fi

echo "==> 1) .app 빌드 (아이콘 포함)"
# build_app.sh 의 로컬 WebDock Dev 서명 대신, 아래에서 Developer ID 로 다시 서명
./build_app.sh

echo "==> 2) Developer ID + Hardened Runtime 서명"
# 공증 필수: runtime + timestamp
codesign --force --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$APP/Contents/MacOS/WebDock"

codesign --force --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$APP"

echo "==> 서명 검증"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority|Identifier|TeamIdentifier|flags|Timestamp' || true
spctl -a -vv "$APP" 2>&1 || true

echo "==> 3) 공증용 zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 4) notarytool 제출 (수 분 걸릴 수 있음)"
# notarytool 은 key 파일을 특정 이름/위치로 요구할 수 있어 임시 복사
KEY_TMP=$(mktemp -d)
trap 'rm -rf "$KEY_TMP"' EXIT
cp "$APPLE_API_KEY_PATH" "$KEY_TMP/AuthKey_${APPLE_API_KEY_ID}.p8"

xcrun notarytool submit "$ZIP" \
  --key "$KEY_TMP/AuthKey_${APPLE_API_KEY_ID}.p8" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" \
  --wait

echo "==> 5) 스테이플"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

mkdir -p "$DIST_DIR"
STAMP=$(date +%Y%m%d)
OUT_ZIP="$DIST_DIR/WebDock-macOS-${STAMP}.zip"
rm -f "$OUT_ZIP"
ditto -c -k --keepParent "$APP" "$OUT_ZIP"

echo ""
echo "완료."
echo "  공증된 앱: $APP"
echo "  배포용 zip: $OUT_ZIP"
echo "  (선택) 홈에 설치: ditto \"$APP\" \"\$HOME/WebDock.app\""
echo ""
echo "Gatekeeper 검사:"
spctl -a -vv "$APP" 2>&1 || true

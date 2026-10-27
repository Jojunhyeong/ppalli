#!/bin/bash
# 배포용 파일 만들기 → build/Ppalli-<버전>.dmg (끌어다 설치), build/Ppalli-<버전>.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-1.0.0}"
export VERSION
APP="$ROOT/build/Ppalli.app"
[ -d "$APP" ] || "$ROOT/scripts/build-app.sh"

STAGE="$ROOT/build/dmg"
DMG="$ROOT/build/Ppalli-$VERSION.dmg"
ZIP="$ROOT/build/Ppalli-$VERSION.zip"
rm -rf "$STAGE" "$DMG" "$ZIP"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"     # 창 안에서 Ppalli를 Applications로 끌어다 놓기

echo "💿 DMG 만드는 중..."
hdiutil create -volname "Ppalli $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "🗜  ZIP 만드는 중..."
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✅ $DMG"
echo "✅ $ZIP"

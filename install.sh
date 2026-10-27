#!/bin/bash
# 소스에서 직접 빌드해서 설치 (DMG를 받는 대신 쓰는 방법)
#   ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

./scripts/build-app.sh

if [ -w /Applications ]; then DEST=/Applications; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
pkill -x Whip 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Whip.app"
cp -R build/Whip.app "$DEST/"

echo "🚀 실행!"
open "$DEST/Whip.app"
echo ""
echo "✅ 설치 완료: $DEST/Whip.app"
echo "   Dock 아이콘 클릭 = 채찍 모드 켜기 · ⌥ESC = 어디서든 켜기/끄기"

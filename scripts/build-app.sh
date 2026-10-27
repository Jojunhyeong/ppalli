#!/bin/bash
# Ppalli.app 빌드 → build/Ppalli.app
# Apple Silicon + Intel 둘 다 되는 universal 앱으로 만듦 (한쪽이 안 되면 이 Mac용으로만)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-1.0.0}"
SRC="$ROOT/Sources/ppalli.swift"
OUT="$ROOT/build"
APP="$OUT/Ppalli.app"
MIN_MACOS=13.0

rm -rf "$OUT"
mkdir -p "$OUT"

compile() {   # compile <arch> <output> [extra swiftc args...]
  local arch=$1 out=$2; shift 2
  swiftc -O -target "$arch-apple-macos$MIN_MACOS" "$@" "$SRC" -o "$out"
}

build_arch() {
  local arch=$1 out=$2
  if compile "$arch" "$out" 2>/dev/null; then return 0; fi
  # 컴파일러와 SDK 버전이 안 맞을 때: 설치된 SDK를 최신부터 하나씩 시도
  local sdks
  sdks=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX[0-9]*.sdk \
               /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX[0-9]*.sdk \
               2>/dev/null | sort -V -r || true)
  for sdk in $sdks; do
    if compile "$arch" "$out" -sdk "$sdk" 2>/dev/null; then
      echo "   ($arch: $(basename "$sdk") 사용)"
      return 0
    fi
  done
  return 1
}

echo "🔨 Ppalli v$VERSION 빌드 중..."
HOST=$(uname -m)
OTHER=$([ "$HOST" = "arm64" ] && echo x86_64 || echo arm64)

if ! build_arch "$HOST" "$OUT/Ppalli-$HOST"; then
  echo "❌ 빌드 실패. 에러 내용:"
  compile "$HOST" "$OUT/Ppalli-$HOST" || true
  exit 1
fi
if build_arch "$OTHER" "$OUT/Ppalli-$OTHER"; then
  lipo -create "$OUT/Ppalli-$HOST" "$OUT/Ppalli-$OTHER" -output "$OUT/Ppalli"
  echo "   Apple Silicon + Intel 모두 지원"
else
  cp "$OUT/Ppalli-$HOST" "$OUT/Ppalli"
  echo "   ($OTHER용은 건너뜀 - 이 Mac 전용)"
fi

echo "📦 앱 묶는 중..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$OUT/Ppalli" "$APP/Contents/MacOS/Ppalli"
rm -f "$OUT"/Ppalli-*
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# 개발자 인증서 없이 만드는 기본 서명 (Apple Silicon에서 실행하려면 필요)
codesign --force --deep --sign - "$APP"

echo "✅ $APP"

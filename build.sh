#!/bin/bash
# NiceShot を .app バンドルとしてビルドする。
# 画面収録の許可は .app 単位で付与されるため、実行ファイル単体ではなくバンドル化が必要。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="NiceShot.app"
BUILD_DIR=".build/$CONFIG"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

echo "==> .app バンドルを作成"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD_DIR/NiceShot" "$APP/Contents/MacOS/NiceShot"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# TCC（画面収録の許可）はコード署名の identity に紐づく。
# adhoc 署名はビルドごとに cdhash が変わり許可が無効化されるため、
# 安定した署名証明書（Apple Development / Developer ID）があればそれで署名する。
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development|Developer ID/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
    echo "==> 署名 (identity: $IDENTITY)"
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "==> 署名証明書が無いため ad-hoc 署名（ビルドごとに再許可が必要になります）"
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "==> 完了: $ROOT/$APP"
echo "    起動: open \"$ROOT/$APP\"   （初回はメニューバーから撮影時に画面収録の許可を求められます）"

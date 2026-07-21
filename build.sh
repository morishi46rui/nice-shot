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
# ビルドごとに署名 identity が変わると許可が無効化されるため、使う証明書を1つに固定する。
# 優先順位: 環境変数 SIGN_IDENTITY > .signing-identity ファイル > 自動検出（先頭）
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && [ -f "$ROOT/.signing-identity" ]; then
    IDENTITY="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/.signing-identity" | head -1 | tr -d '[:space:]')"
fi
if [ -z "$IDENTITY" ]; then
    CERTS="$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development|Developer ID' || true)"
    COUNT="$(printf '%s\n' "$CERTS" | grep -c . || true)"
    IDENTITY="$(printf '%s\n' "$CERTS" | awk '{print $2; exit}')"
    if [ "${COUNT:-0}" -gt 1 ]; then
        echo "⚠️  署名証明書が複数あります。TCC(画面収録)の許可を安定させるには使う証明書を固定してください:"
        echo "    security find-identity -v -p codesigning   # SHA1 を確認"
        echo "    echo <SHA1> > .signing-identity            # 1つに固定（gitには含まれません）"
    fi
fi

if [ -n "$IDENTITY" ]; then
    echo "==> 署名 (identity: $IDENTITY)"
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "==> 署名証明書が無いため ad-hoc 署名（ビルドごとに再許可が必要になります）"
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "==> 完了: $ROOT/$APP"
echo "    起動: open \"$ROOT/$APP\"   （初回はメニューバーから撮影時に画面収録の許可を求められます）"

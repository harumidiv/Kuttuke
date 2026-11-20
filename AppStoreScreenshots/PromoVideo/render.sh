#!/bin/zsh
# App Store の検索結果（3840×2560）用の動画を書き出す
# 使い方（どこからでも）:
#   AppStoreScreenshots/PromoVideo/render.sh            # 動画を書き出す
#   AppStoreScreenshots/PromoVideo/render.sh --stills   # 確認用の静止画だけ書き出す（黄色: セーフエリア、水色: 検索結果で見える範囲）
# 入力: AppStoreScreenshots/header-assets/*.png（切り抜き素材）
# 出力: AppStoreScreenshots/PromoVideo/output/search_3840x2560.mp4
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD_DIR=${TMPDIR:-/tmp}/kuttuke_promo_video
mkdir -p "$BUILD_DIR"
swiftc -O -o "$BUILD_DIR/render_promo" "$ROOT/AppStoreScreenshots/PromoVideo/main.swift"
cd "$ROOT"
"$BUILD_DIR/render_promo" "$@"

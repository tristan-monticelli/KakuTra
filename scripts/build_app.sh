#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "=========================================="
echo "  KakuTra - Build & Packaging Automation  "
echo "=========================================="

echo "==> Building KakuTra Direct distribution..."
SCHEME="KakuTra Direct" ./scripts/build/package-app.sh

echo "==> Build successfully completed!"
echo "    App bundle: dist/DerivedData/Build/Products/Release/KakuTra.app"
echo "    DMG installer: $(ls dist/*.dmg 2>/dev/null || echo 'dist/')"

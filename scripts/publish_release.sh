#!/usr/bin/env bash
set -euo pipefail

# Publishes a signed Android release APK to GitHub Releases (`spideynk25/worship_chat`).
# Usage:
#   ./scripts/publish_release.sh               # builds release APK & uploads GitHub Release
#   ./scripts/publish_release.sh --skip-build  # uses existing build/app/outputs/flutter-apk/app-release.apk

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

REPO="spideynk25/worship_chat"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

RAW_VERSION="$(grep -E '^version:' pubspec.yaml | head -n1 | awk '{print $2}' | tr -d '\r')"
VERSION_NAME="${RAW_VERSION%%+*}"
BUILD_NUMBER="${RAW_VERSION##*+}"
if [[ "$VERSION_NAME" == "$RAW_VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "❌ Invalid version line in pubspec.yaml: '$RAW_VERSION' (expected e.g. 1.0.1+2)"
  exit 1
fi

TAG="v${VERSION_NAME}-b${BUILD_NUMBER}"
TITLE="Worship Chat v${VERSION_NAME} (Build ${BUILD_NUMBER})"

if [[ "${1:-}" != "--skip-build" ]]; then
  echo "🔨 Building release APK for $TITLE..."
  flutter build apk --release
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "❌ APK not found at $APK_PATH"
  exit 1
fi

SHA256="$(shasum -a 256 "$APK_PATH" | awk '{print $1}')"
SIZE_MB="$(du -m "$APK_PATH" | awk '{print $1}')"

NOTES="Worship Chat Android Release v${VERSION_NAME} (Build ${BUILD_NUMBER})
sha256: ${SHA256}"

echo ""
echo "📦 Ready Release Asset:"
echo "   Repo    : $REPO"
echo "   Tag     : $TAG"
echo "   APK     : $APK_PATH (${SIZE_MB} MB)"
echo "   SHA-256 : $SHA256"
echo ""

if ! command -v gh >/dev/null 2>&1; then
  echo "⚠️  GitHub CLI ('gh') is not installed yet."
  echo "   Install & authenticate once with:"
  echo "     brew install gh && gh auth login"
  echo "   Or upload manually in browser at:"
  echo "     https://github.com/$REPO/releases/new?tag=$TAG"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "⚠️  GitHub CLI is not authenticated. Run:"
  echo "     gh auth login"
  echo "   Then re-run:"
  echo "     ./scripts/publish_release.sh --skip-build"
  exit 1
fi

echo "🚀 Creating GitHub Release $TAG (uploading ${SIZE_MB} MB APK)..."
gh release create "$TAG" "$APK_PATH" \
  --repo "$REPO" \
  --target main \
  --title "$TITLE" \
  --notes "$NOTES"

echo ""
echo "✅ Published! Direct APK URL:"
echo "   https://github.com/$REPO/releases/download/$TAG/app-release.apk"

if command -v curl >/dev/null 2>&1; then
  echo "📣 Sending app update push notification to topic 'app_updates'..."
  PAYLOAD="$(printf '{"versionName":"%s","versionCode":%s,"releaseNotes":"%s"}' \
    "$VERSION_NAME" "$BUILD_NUMBER" "Tap to download Worship Chat v${VERSION_NAME} (Build ${BUILD_NUMBER}).")"
  curl -fsS --max-time 8 -X POST "https://worshipchatnotification.vercel.app/notify-update" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null 2>&1 && \
    echo "✅ Update push notification sent!" || \
    echo "ℹ️  Remote notify endpoint skipped/unavailable (phones still auto-detect & notify)."
fi

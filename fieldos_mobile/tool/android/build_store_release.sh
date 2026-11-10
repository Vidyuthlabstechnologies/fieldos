#!/usr/bin/env bash
# Builds the Play Store copy of FieldOS (release APK + App Bundle).
#
# Used by .github/workflows/release.yml and by hand on any Linux/Mac/WSL
# machine with Flutter and the Android SDK (no GitHub Actions needed).
#
# Needs these environment variables:
#   SUPABASE_URL, SUPABASE_ANON_KEY   the production project (https://<ref>.supabase.co)
#   REVENUECAT_ANDROID_KEY            RevenueCat's PUBLIC Google key (goog_...)
# and the upload key: android/app/key.properties + the keystore it names.
# Optional:
#   GOOGLE_WEB_CLIENT_ID              "Continue with Google"
#   PRIVACY_POLICY_URL, TERMS_URL     default: the live FieldOS website
#   REVENUECAT_IOS_KEY                passed through, unused on Android
#
# It refuses to build when any of those is missing. A build without them
# installs and opens fine, but has cloud sync hidden or no paywall at all
# (everything free), and must never reach the Play Store. The app checks
# again on start (lib/core/release_config.dart).
set -euo pipefail
cd "$(dirname "$0")/../.."   # fieldos_mobile/

fail() { echo "error: $*" >&2; exit 1; }

missing=""
for v in SUPABASE_URL SUPABASE_ANON_KEY REVENUECAT_ANDROID_KEY; do
  [ -n "${!v:-}" ] || missing="$missing $v"
done
[ -z "$missing" ] || fail "missing:$missing (see docs/PLAY_STORE_LAUNCH.md)"

case "$SUPABASE_URL" in
  https://*.supabase.co|https://*.supabase.co/) ;;
  *) fail "SUPABASE_URL should be the production project, https://<ref>.supabase.co (got $SUPABASE_URL)" ;;
esac
case "$SUPABASE_ANON_KEY" in
  eyJ*|sb_publishable_*) ;;
  *) fail "SUPABASE_ANON_KEY does not look like an anon/publishable key" ;;
esac
# The service_role key bypasses row level security: never ship it.
if [ "${SUPABASE_ANON_KEY#eyJ}" != "$SUPABASE_ANON_KEY" ]; then
  body=$(printf '%s' "$SUPABASE_ANON_KEY" | cut -d. -f2 | tr '_-' '/+')
  while [ $(( ${#body} % 4 )) -ne 0 ]; do body="$body="; done
  role=$(printf '%s' "$body" | base64 -d 2>/dev/null | tr -d ' ' | grep -o '"role":"[a-z_]*"' || true)
  [ "$role" != '"role":"service_role"' ] || fail "SUPABASE_ANON_KEY is the service_role key; use the anon key"
fi
case "$SUPABASE_ANON_KEY" in sb_secret_*) fail "SUPABASE_ANON_KEY is a secret key; use the publishable key" ;; esac
case "$REVENUECAT_ANDROID_KEY" in
  goog_*) ;;
  *) fail "REVENUECAT_ANDROID_KEY should be the Google public SDK key (starts with goog_)" ;;
esac

[ -f android/app/key.properties ] || fail "android/app/key.properties missing: a store build must be signed with the upload key"
store_file=$(sed -n 's/^storeFile=//p' android/app/key.properties)
[ -n "$store_file" ] && [ -f "android/app/$store_file" ] || fail "the keystore named in key.properties ($store_file) is not in android/app/"

PRIVACY_POLICY_URL="${PRIVACY_POLICY_URL:-https://fieldos-mldynamic.netlify.app/privacy-policy.html}"
TERMS_URL="${TERMS_URL:-https://fieldos-mldynamic.netlify.app/terms-of-use.html}"

defines=(
  "--dart-define=FIELDOS_STORE_RELEASE=true"
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
  "--dart-define=REVENUECAT_ANDROID_KEY=$REVENUECAT_ANDROID_KEY"
  "--dart-define=REVENUECAT_IOS_KEY=${REVENUECAT_IOS_KEY:-}"
  "--dart-define=PRIVACY_POLICY_URL=$PRIVACY_POLICY_URL"
  "--dart-define=TERMS_URL=$TERMS_URL"
  "--dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}"
)

if [ "${PREFLIGHT_ONLY:-}" = "1" ]; then
  echo "preflight ok"
  exit 0
fi

flutter pub get
flutter build apk --release "${defines[@]}"
flutter build appbundle --release "${defines[@]}"
ls -l build/app/outputs/flutter-apk/app-release.apk build/app/outputs/bundle/release/app-release.aab

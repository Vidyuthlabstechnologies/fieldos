#!/usr/bin/env bash
# Builds the App Store copy of FieldOS for iPhone (an .ipa), on a Mac.
#
# Used by codemagic.yaml (free Mac builds, no GitHub Actions) and by hand on
# your own Mac. Steps for both are in docs/APP_STORE_LAUNCH.md.
#
# Needs these environment variables (the same values as the Android build):
#   SUPABASE_URL, SUPABASE_ANON_KEY   Team & sync (the production project)
#   REVENUECAT_IOS_KEY                RevenueCat's PUBLIC Apple key (appl_...)
# Optional:
#   FIELDOS_MARKET                    in (default), us, my, ae or uk: which
#                                     country's app; sets the bundle id
#                                     (com.mldynamic.fieldos.us ...) through
#                                     ios/Flutter/Market.xcconfig
#   GOOGLE_WEB_CLIENT_ID + GOOGLE_IOS_CLIENT_ID   "Continue with Google"
#   PRIVACY_POLICY_URL, TERMS_URL     default: the live FieldOS website
#   BUILD_NUMBER                      default: the +N in pubspec.yaml
#   EXPORT_OPTIONS_PLIST              set by Codemagic's signing step
#
# It refuses to build without the RevenueCat key: such a build has no
# paywall at all, and must never reach the App Store.
set -euo pipefail
cd "$(dirname "$0")/../.."   # fieldos_mobile/

missing=""
for v in SUPABASE_URL SUPABASE_ANON_KEY REVENUECAT_IOS_KEY; do
  [ -n "${!v:-}" ] || missing="$missing $v"
done
if [ -n "$missing" ]; then
  echo "error: missing:$missing (see docs/APP_STORE_LAUNCH.md)" >&2
  exit 1
fi
case "$REVENUECAT_IOS_KEY" in
  appl_*) ;;
  *) echo "error: REVENUECAT_IOS_KEY should be the Apple public SDK key (starts with appl_)" >&2; exit 1 ;;
esac

FIELDOS_MARKET="${FIELDOS_MARKET:-in}"
case "$FIELDOS_MARKET" in
  in) suffix="" ;;
  us|my|ae|uk) suffix=".$FIELDOS_MARKET" ;;
  *) echo "error: FIELDOS_MARKET should be in, us, my, ae or uk (got $FIELDOS_MARKET)" >&2; exit 1 ;;
esac
sed -i.bak "s|^FIELDOS_BUNDLE_SUFFIX =.*|FIELDOS_BUNDLE_SUFFIX = $suffix|" ios/Flutter/Market.xcconfig
rm -f ios/Flutter/Market.xcconfig.bak
echo "Building the $FIELDOS_MARKET app: com.mldynamic.fieldos$suffix"

PRIVACY_POLICY_URL="${PRIVACY_POLICY_URL:-https://fieldos-mldynamic.netlify.app/privacy-policy.html}"
TERMS_URL="${TERMS_URL:-https://fieldos-mldynamic.netlify.app/terms-of-use.html}"
GOOGLE_WEB_CLIENT_ID="${GOOGLE_WEB_CLIENT_ID:-}"
GOOGLE_IOS_CLIENT_ID="${GOOGLE_IOS_CLIENT_ID:-}"

# Google sign-in returns to the app through the reversed iOS client id.
if [ -n "$GOOGLE_IOS_CLIENT_ID" ]; then
  if [ -z "$GOOGLE_WEB_CLIENT_ID" ]; then
    echo "error: GOOGLE_IOS_CLIENT_ID needs GOOGLE_WEB_CLIENT_ID too" >&2
    exit 1
  fi
  case "$GOOGLE_IOS_CLIENT_ID" in
    *.apps.googleusercontent.com) ;;
    *) echo "error: GOOGLE_IOS_CLIENT_ID should end in .apps.googleusercontent.com" >&2; exit 1 ;;
  esac
  reversed="com.googleusercontent.apps.${GOOGLE_IOS_CLIENT_ID%.apps.googleusercontent.com}"
  sed -i.bak "s|^GOOGLE_REVERSED_CLIENT_ID = .*|GOOGLE_REVERSED_CLIENT_ID = $reversed|" ios/Flutter/Google.xcconfig
  rm -f ios/Flutter/Google.xcconfig.bak
  echo "Google sign-in on: $reversed"
else
  echo "Google sign-in off on iPhone (no GOOGLE_IOS_CLIENT_ID); Sign in with Apple and username/password stay."
fi

args=(build ipa --release
  "--dart-define=FIELDOS_STORE_RELEASE=true"
  "--dart-define=FIELDOS_MARKET=$FIELDOS_MARKET"
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
  "--dart-define=REVENUECAT_IOS_KEY=$REVENUECAT_IOS_KEY"
  "--dart-define=PRIVACY_POLICY_URL=$PRIVACY_POLICY_URL"
  "--dart-define=TERMS_URL=$TERMS_URL"
  "--dart-define=GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID"
  "--dart-define=GOOGLE_IOS_CLIENT_ID=$GOOGLE_IOS_CLIENT_ID")
[ -n "${BUILD_NUMBER:-}" ] && args+=("--build-number=$BUILD_NUMBER")
[ -n "${EXPORT_OPTIONS_PLIST:-}" ] && args+=("--export-options-plist=$EXPORT_OPTIONS_PLIST")

flutter pub get
flutter "${args[@]}"
ls -l build/ios/ipa/*.ipa

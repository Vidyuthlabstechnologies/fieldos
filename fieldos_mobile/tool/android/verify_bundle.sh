#!/usr/bin/env bash
# Checks a FieldOS App Bundle before it is uploaded to Google Play:
#   - the package is com.mldynamic.fieldos (PACKAGE_NAME overrides)
#   - the versionCode is VERSION_CODE (when set; the play-upload workflow
#     passes the one from pubspec.yaml)
#   - it is signed with the upload key whose SHA-1 is UPLOAD_KEY_SHA1
#
# Usage: verify_bundle.sh path/to/app-release.aab
# Needs java + keytool. Downloads bundletool once unless BUNDLETOOL_JAR
# points at a copy. Used by .github/workflows/play-upload.yml; also works
# by hand on any machine with Java.
set -euo pipefail

aab="${1:?usage: verify_bundle.sh app-release.aab}"
[ -f "$aab" ] || { echo "error: $aab not found" >&2; exit 1; }

PACKAGE_NAME="${PACKAGE_NAME:-com.mldynamic.fieldos}"
UPLOAD_KEY_SHA1="${UPLOAD_KEY_SHA1:-93:C0:C1:A6:14:D8:2E:C3:29:02:FF:C2:10:F0:9D:D8:18:7E:4D:A4}"
BUNDLETOOL_VERSION="1.18.1"

fail() { echo "error: $*" >&2; exit 1; }

jar="${BUNDLETOOL_JAR:-}"
if [ -z "$jar" ]; then
  jar="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/bundletool-$BUNDLETOOL_VERSION.jar"
  [ -f "$jar" ] || curl -fsSL -o "$jar" \
    "https://github.com/google/bundletool/releases/download/$BUNDLETOOL_VERSION/bundletool-all-$BUNDLETOOL_VERSION.jar"
fi

dump() { java -jar "$jar" dump manifest --bundle "$aab" --xpath "$1" | tr -d '[:space:]'; }

pkg=$(dump /manifest/@package)
[ "$pkg" = "$PACKAGE_NAME" ] || fail "bundle package is '$pkg', expected '$PACKAGE_NAME'"
echo "package:     $pkg"

code=$(dump /manifest/@android:versionCode)
if [ -n "${VERSION_CODE:-}" ]; then
  [ "$code" = "$VERSION_CODE" ] || fail "bundle versionCode is $code, pubspec.yaml says $VERSION_CODE (stale build?)"
fi
echo "versionCode: $code"

want=$(printf '%s' "$UPLOAD_KEY_SHA1" | tr -d ': ' | tr '[:lower:]' '[:upper:]')
certs=$(keytool -printcert -jarfile "$aab" 2>/dev/null || true)
[ -n "$certs" ] || fail "bundle is not signed"
got=$(printf '%s\n' "$certs" | sed -n 's/.*SHA1: *\([0-9A-Fa-f:]*\).*/\1/p' | head -n1 | tr -d ':' | tr '[:lower:]' '[:upper:]')
[ -n "$got" ] || fail "could not read the signing certificate's SHA-1"
if [ "$got" != "$want" ]; then
  if printf '%s\n' "$certs" | grep -q "CN=Android Debug"; then
    fail "bundle is signed with the DEBUG key; Play needs the upload key"
  fi
  fail "bundle is signed with SHA-1 $got, not the upload key $want"
fi
echo "signed with: upload key ($UPLOAD_KEY_SHA1)"
echo "bundle ok"

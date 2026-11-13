#!/usr/bin/env bash
# Sets the Play Store launch secrets on the GitHub repo from one local file,
# instead of pasting ten values into Settings -> Secrets one at a time.
#
#   cp launch-secrets.env.example launch-secrets.env   # fill in; it is gitignored
#   tools/set_launch_secrets.sh                        # or: tools/set_launch_secrets.sh path/to/file
#
# Only the repository OWNER can set secrets on a personal GitHub repo; a
# collaborator with write access gets HTTP 403. So this runs on the owner's
# computer, signed in with `gh auth login` as the owner. Afterwards anyone
# can run the launch-readiness workflow from the Actions tab to see what is
# set and whether each value is the right kind of key.
#
# Lines that are blank, comments, or have an empty value are skipped, so a
# partly filled file sets only what it has. ANDROID_KEYSTORE_FILE (a path to
# the upload .keystore/.jks) is base64-encoded into ANDROID_KEYSTORE_BASE64.
# PLAY_SERVICE_ACCOUNT_FILE (a path to the Play service account's .json key)
# is read into PLAY_SERVICE_ACCOUNT_JSON.
set -euo pipefail

FILE=${1:-launch-secrets.env}
if [ ! -f "$FILE" ]; then
  echo "No $FILE. Copy launch-secrets.env.example to launch-secrets.env and fill it in." >&2
  exit 1
fi
REPO=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

NAMES="SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD \
REVENUECAT_ANDROID_KEY REVENUECAT_IOS_KEY REVENUECAT_SECRET_KEY \
ANTHROPIC_API_KEY SARVAM_API_KEY \
ANDROID_KEYSTORE_BASE64 ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD ANDROID_STORE_PASSWORD \
PLAY_SERVICE_ACCOUNT_JSON"

# Plain KEY=VALUE parsing rather than `source`: passwords may contain $ or
# quotes, and nothing in the file should ever run as shell. Values land in
# LS_<KEY> variables (macOS ships bash 3.2, which has no associative arrays).
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}
  case "$line" in ''|'#'*) continue ;; esac
  key=${line%%=*}
  value=${line#*=}
  key=${key// /}
  case "$key" in *[!A-Za-z0-9_]*|'') echo "Skipping a line that is not NAME=value: ${line%%=*}" >&2; continue ;; esac
  if [ "${value:0:1}" = '"' ] && [ "${value: -1}" = '"' ] && [ ${#value} -ge 2 ]; then
    value=${value:1:${#value}-2}
  fi
  printf -v "LS_$key" '%s' "$value"
done < "$FILE"

if [ -n "${LS_ANDROID_KEYSTORE_FILE:-}" ] && [ -z "${LS_ANDROID_KEYSTORE_BASE64:-}" ]; then
  ks=$LS_ANDROID_KEYSTORE_FILE
  [ -f "$ks" ] || { echo "ANDROID_KEYSTORE_FILE points to $ks, which does not exist." >&2; exit 1; }
  LS_ANDROID_KEYSTORE_BASE64=$(base64 < "$ks" | tr -d '\n')
fi

if [ -n "${LS_PLAY_SERVICE_ACCOUNT_FILE:-}" ] && [ -z "${LS_PLAY_SERVICE_ACCOUNT_JSON:-}" ]; then
  sa=$LS_PLAY_SERVICE_ACCOUNT_FILE
  [ -f "$sa" ] || { echo "PLAY_SERVICE_ACCOUNT_FILE points to $sa, which does not exist." >&2; exit 1; }
  LS_PLAY_SERVICE_ACCOUNT_JSON=$(cat "$sa")
fi

set_count=0
for name in $NAMES; do
  var="LS_$name"
  value=${!var:-}
  if [ -z "$value" ]; then
    echo "skip  $name (empty)"
    continue
  fi
  if printf '%s' "$value" | gh secret set "$name" --repo "$REPO"; then
    echo "set   $name"
    set_count=$((set_count + 1))
  else
    echo "FAILED $name (only the repository owner can set secrets on $REPO)" >&2
    exit 1
  fi
done

echo
echo "$set_count secret(s) set on $REPO."
echo "Next: gh workflow run launch-readiness.yml --repo $REPO   (then open it in the Actions tab)"

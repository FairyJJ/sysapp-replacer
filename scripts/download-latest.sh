#!/usr/bin/env bash
# Download the newest repacked APK from this repo's public releases.
# Pure download — never touches adb, never installs anything.
#
#   ./scripts/download-latest.sh                # both apps -> ./dist
#   ./scripts/download-latest.sh appharbor      # one app
#   OUT=/tmp/apk ./scripts/download-latest.sh   # custom dir
set -euo pipefail

REPO="${REPO:-FairyJJ/sysapp-replacer}"
OUT="${OUT:-./dist}"
mkdir -p "$OUT"

get_latest() {  # $1 = tag prefix -> "<tag>\n<asset-name>\n<browser_download_url>"
  curl -fsSL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases?per_page=50" \
  | python3 -c '
import json,sys
prefix=sys.argv[1]
rels=[r for r in json.load(sys.stdin) if not r.get("draft") and r["tag_name"].startswith(prefix+"-")]
rels.sort(key=lambda r: r.get("published_at") or "", reverse=True)
if not rels: sys.exit(1)
r=rels[0]
apk=[a for a in r["assets"] if a["name"].endswith(".apk")][0]
print(r["tag_name"]); print(apk["name"]); print(apk["browser_download_url"])
' "$1"
}

fetch_one() {
  local app="$1" info tag name url dest
  echo "== $app"
  if ! info=$(get_latest "$app"); then
    echo "  no release yet, skip"; return 0
  fi
  tag=$(echo "$info" | sed -n 1p)
  name=$(echo "$info" | sed -n 2p)
  url=$(echo "$info" | sed -n 3p)
  dest="$OUT/$name"
  echo "  $tag"
  curl -fsSL --retry 3 -o "$dest" "$url"
  echo "  -> $dest  ($(stat -c%s "$dest") bytes)"
  echo "     install: adb install -r -t \"$dest\""
}

case "${1:-all}" in
  appharbor) fetch_one appharbor ;;
  installerx) fetch_one installerx ;;
  all) fetch_one appharbor; fetch_one installerx ;;
  *) echo "usage: $0 [appharbor|installerx|all]" >&2; exit 2 ;;
esac

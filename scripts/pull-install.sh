#!/usr/bin/env bash
# Pull the newest repacked APK from the private GitHub release and install it over adb.
#
#   ./scripts/pull-install.sh            # both apps
#   ./scripts/pull-install.sh appharbor  # only one
#
# Token lookup order: $GH_TOKEN -> ~/.config/sysapp-replacer/token
set -euo pipefail

REPO="${REPO:-FairyJJ/sysapp-replacer}"
CACHE="${CACHE:-$HOME/.cache/sysapp-replacer}"
STATE="$CACHE/state"
mkdir -p "$CACHE" "$STATE"

TOKEN="${GH_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$HOME/.config/sysapp-replacer/token" ]; then
  TOKEN=$(tr -d ' \n\r' < "$HOME/.config/sysapp-replacer/token")
fi
[ -n "$TOKEN" ] || { echo "no token: set GH_TOKEN or ~/.config/sysapp-replacer/token" >&2; exit 1; }

api() { curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

get_latest() {  # $1 = tag prefix
  api "https://api.github.com/repos/$REPO/releases?per_page=50" \
  | python3 -c '
import json,sys
prefix=sys.argv[1]
rels=[r for r in json.load(sys.stdin) if not r.get("draft") and r["tag_name"].startswith(prefix+"-")]
rels.sort(key=lambda r: r.get("published_at") or "", reverse=True)
if not rels: sys.exit("none")
r=rels[0]
apk=[a for a in r["assets"] if a["name"].endswith(".apk")][0]
print(r["tag_name"]); print(apk["browser_download_url"]); print(apk["name"])
' "$1"
}

install_one() {
  local app="$1"
  echo "== $app"
  local info tag url name
  info=$(get_latest "$app" 2>/dev/null) || { echo "  no release yet, skip"; return 0; }
  tag=$(echo "$info" | sed -n 1p)
  url=$(echo "$info" | sed -n 2p)
  name=$(echo "$info" | sed -n 3p)

  local prev=""
  [ -f "$STATE/$app.tag" ] && prev=$(cat "$STATE/$app.tag")
  if [ "$prev" = "$tag" ]; then
    echo "  already at $tag"
    return 0
  fi

  local dest="$CACHE/$name"
  echo "  downloading $name ($tag)"
  curl -fsSL --retry 3 -H "Authorization: Bearer $TOKEN" -o "$dest" "$url"

  if ! adb get-state >/dev/null 2>&1; then
    echo "  no adb device, saved to $dest"
    return 1
  fi

  echo "  installing"
  adb install -r -t "$dest"
  echo "$tag" > "$STATE/$app.tag"
  echo "  done -> $tag"
}

case "${1:-all}" in
  appharbor) install_one appharbor ;;
  installerx) install_one installerx ;;
  all) install_one appharbor; install_one installerx ;;
  *) echo "usage: $0 [appharbor|installerx|all]" >&2; exit 2 ;;
esac

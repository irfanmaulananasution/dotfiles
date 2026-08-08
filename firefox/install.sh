#!/usr/bin/env bash
#
# Configure Firefox: vertical tabs, extensions, bookmarks
set -euo pipefail

FIREFOX_PROFILES="$HOME/Library/Application Support/Firefox/Profiles"

if [ ! -d "$FIREFOX_PROFILES" ]; then
  echo "  [..] Firefox profiles directory not found — skipping"
  exit 0
fi

# Find the default-release profile
profile=""
for dir in "$FIREFOX_PROFILES"/*.default-release "$FIREFOX_PROFILES"/*.default; do
  if [ -d "$dir" ]; then
    profile="$dir"
    break
  fi
done

if [ -z "$profile" ]; then
  echo "  [..] No Firefox profile found — skipping"
  exit 0
fi

# ---------- Preferences (user.js) ----------
cat >> "$profile/user.js" << 'EOF'

// Enable vertical tabs in the sidebar
user_pref("sidebar.verticalTabs", true);
user_pref("sidebar.visibility", "always");
// Don't disable extensions placed in the profile's extensions/ folder
user_pref("extensions.autoDisableScopes", 0);
EOF

# ---------- Extensions (XPI files) ----------
EXT_DIR="$profile/extensions"
mkdir -p "$EXT_DIR"

install_ext() {
  local id="$1"
  local url="$2"
  local path="$EXT_DIR/$id.xpi"

  if [ -f "$path" ]; then
    echo "  [ OK] $id already installed"
    return
  fi

  echo "  [..] Downloading $id ..."
  if curl -sfL "$url" -o "$path" 2>/dev/null && [ -s "$path" ]; then
    echo "  [ OK] $id installed"
  else
    rm -f "$path"
    echo "  [WARN] Failed to download $id"
  fi
}

install_ext "uBlock0@raymondhill.net" \
  "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"

install_ext "{b9db16a4-6edc-47ec-a1f4-b86292ed211d}" \
  "https://addons.mozilla.org/firefox/downloads/latest/video-downloadhelper/latest.xpi"

echo "  [ OK] Firefox configured"

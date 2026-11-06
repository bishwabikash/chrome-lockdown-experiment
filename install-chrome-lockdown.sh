#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="$SRC_DIR/lockdown.json"
NOEXT="$SRC_DIR/no-extensions.json"
BLOCK_EXTENSIONS="${BLOCK_EXTENSIONS:-0}"
CLEAN_OTHER_BROWSERS="${CLEAN_OTHER_BROWSERS:-0}"

POLICY_NAME="99-chrome-lockdown.json"
NOEXT_NAME="99-chrome-no-extensions.json"
LEGACY_NAMES=(lockdown.json no-extensions.json)

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
[[ -f "$POLICY" ]] || { echo "lockdown.json not found next to this script" >&2; exit 1; }

command -v python3 >/dev/null && python3 -I -c 'import json,sys;json.load(open(sys.argv[1]))' "$POLICY"

declare -A TARGETS=(
  ["/etc/opt/chrome/policies/managed"]="/opt/google/chrome"
  ["/etc/opt/chrome-beta/policies/managed"]="/opt/google/chrome-beta"
  ["/etc/opt/chrome-unstable/policies/managed"]="/opt/google/chrome-unstable"
)

FOREIGN=(
  /etc/brave/policies/managed
  /etc/chromium/policies/managed
  /etc/chromium-browser/policies/managed
  /etc/opt/edge/policies/managed
)

if [[ "$CLEAN_OTHER_BROWSERS" == "1" ]]; then
  for dir in "${FOREIGN[@]}"; do
    for f in "$POLICY_NAME" "$NOEXT_NAME" "${LEGACY_NAMES[@]}"; do
      if [[ -f "$dir/$f" ]]; then
        rm -f "$dir/$f"
        echo "DELETED $dir/$f"
      fi
    done
  done
fi

INSTALLED=0
for dir in "${!TARGETS[@]}"; do
  [[ -d "${TARGETS[$dir]}" || -d "${dir%/policies/managed}" ]] || continue
  install -d -m 755 "$dir"
  install -o root -g root -m 644 "$POLICY" "$dir/$POLICY_NAME"

  if [[ "$BLOCK_EXTENSIONS" == "1" ]]; then
    install -o root -g root -m 644 "$NOEXT" "$dir/$NOEXT_NAME"
  else
    rm -f "$dir/$NOEXT_NAME"
  fi

  for f in "${LEGACY_NAMES[@]}"; do
    [[ -f "$dir/$f" ]] && rm -f "$dir/$f" && echo "removed legacy $dir/$f"
  done

  echo "policy -> $dir/$POLICY_NAME"
  INSTALLED=1
done

[[ $INSTALLED -eq 1 ]] || { echo "no Google Chrome install detected" >&2; exit 1; }

for base in /opt/google/chrome /opt/google/chrome-beta /opt/google/chrome-unstable; do
  [[ -d "$base" ]] || continue
  pref="$base/initial_preferences"
  cat > "$pref" <<'EOF'
{
  "distribution": {
    "import_bookmarks": false,
    "import_history": false,
    "import_search_engine": false,
    "make_chrome_default": false,
    "make_chrome_default_for_user": false,
    "skip_first_run_ui": true,
    "suppress_first_run_bubble": true,
    "suppress_first_run_default_browser_prompt": true,
    "do_not_create_desktop_shortcut": true,
    "do_not_create_quick_launch_shortcut": true,
    "do_not_create_taskbar_shortcut": true,
    "do_not_launch_chrome": true,
    "do_not_register_for_update_launch": true,
    "verbose_logging": false
  },
  "first_run_tabs": [],
  "browser": { "show_home_button": false, "check_default_browser": false },
  "sync_promo": { "show_on_first_run_allowed": false, "user_skipped": true },
  "default_search_provider_data": { "keyword": "ddg" }
}
EOF
  chmod 644 "$pref"
  echo "initial_preferences -> $pref"
done

for unit in google-chrome.list google-chrome-beta.list google-chrome-unstable.list; do
  [[ -f "/etc/apt/sources.list.d/$unit" ]] && echo "note: $unit still present (Google repo pings on apt update)"
done

echo
echo "done. restart Chrome, then open chrome://policy and click 'Reload policies'."

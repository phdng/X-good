#!/usr/bin/env bash
set -euo pipefail

: "${THEOS:?THEOS must be set}"

TMP_DIR="${TMP_DIR:-$(mktemp -d)}"
ALT_DIR="$TMP_DIR/AltList"

git clone --depth=1 https://github.com/opa334/AltList.git "$ALT_DIR"

HEADER_PATH="$(find "$ALT_DIR" -name ATLApplicationListMultiSelectionController.h -print -quit)"
if [[ -n "$HEADER_PATH" ]]; then
  HEADER_DIR="$(dirname "$HEADER_PATH")"
  mkdir -p "$THEOS/include/AltList"
  cp -R "$HEADER_DIR/"* "$THEOS/include/AltList/"
else
  echo "AltList headers not found" >&2
  exit 1
fi

DEB_URL="$(python3 - <<'PY'
import json
import urllib.request
url = "https://api.github.com/repos/opa334/AltList/releases/latest"
with urllib.request.urlopen(url) as response:
    data = json.load(response)
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(".deb"):
        print(asset.get("browser_download_url", ""))
        break
PY
)"

if [[ -z "$DEB_URL" ]]; then
  echo "AltList release .deb not found" >&2
  exit 1
fi

curl -fsSL "$DEB_URL" -o "$TMP_DIR/AltList.deb"

dpkg-deb -x "$TMP_DIR/AltList.deb" "$TMP_DIR/altlist_extract"
FRAMEWORK_PATH="$(find "$TMP_DIR/altlist_extract" -name AltList.framework -print -quit)"
if [[ -n "$FRAMEWORK_PATH" ]]; then
  mkdir -p "$THEOS/lib"
  cp -R "$FRAMEWORK_PATH" "$THEOS/lib/"
  if [[ -d "$FRAMEWORK_PATH/Headers" ]]; then
    mkdir -p "$THEOS/include/AltList"
    cp -R "$FRAMEWORK_PATH/Headers/"* "$THEOS/include/AltList/"
  fi
else
  echo "AltList.framework not found in release .deb" >&2
  exit 1
fi

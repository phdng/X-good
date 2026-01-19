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

DERIVED_DATA_PATH="$TMP_DIR/altlist_derived"
BUILD_CONFIGURATION="Release"

if [[ -d "$ALT_DIR/AltList.xcworkspace" ]]; then
  xcodebuild \
    -workspace "$ALT_DIR/AltList.xcworkspace" \
    -scheme "AltList" \
    -configuration "$BUILD_CONFIGURATION" \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_IDENTITY=""
elif [[ -d "$ALT_DIR/AltList.xcodeproj" ]]; then
  xcodebuild \
    -project "$ALT_DIR/AltList.xcodeproj" \
    -scheme "AltList" \
    -configuration "$BUILD_CONFIGURATION" \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_IDENTITY=""
else
  echo "AltList Xcode project/workspace not found; cannot build framework." >&2
  exit 1
fi

FRAMEWORK_PATH="$(find "$DERIVED_DATA_PATH" -name AltList.framework -print -quit)"
if [[ -n "$FRAMEWORK_PATH" ]]; then
  mkdir -p "$THEOS/lib"
  cp -R "$FRAMEWORK_PATH" "$THEOS/lib/"
  if [[ -d "$FRAMEWORK_PATH/Headers" ]]; then
    mkdir -p "$THEOS/include/AltList"
    cp -R "$FRAMEWORK_PATH/Headers/"* "$THEOS/include/AltList/"
  fi
else
  echo "AltList.framework not found in build output." >&2
  exit 1
fi

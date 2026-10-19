#!/bin/bash
set -euo pipefail
app_path=$1
identity=$2
framework="$app_path/Contents/Frameworks/Sparkle.framework"
# Xcode's direct build signs the framework, but not its nested helpers.
for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    codesign --force --sign "$identity" --options runtime --timestamp \
        --preserve-metadata=entitlements "$framework/Versions/B/$helper"
done
codesign --force --sign "$identity" --options runtime --timestamp "$framework"
codesign --force --sign "$identity" --options runtime --timestamp \
    --preserve-metadata=entitlements "$app_path"
codesign --verify --deep --strict "$app_path"

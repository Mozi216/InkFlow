#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${IOS_CERTIFICATE_BASE64:?Missing distribution certificate}"
: "${IOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${IOS_APP_PROFILE_BASE64:?Missing app profile}"
: "${IOS_WIDGET_PROFILE_BASE64:?Missing widget profile}"
: "${IOS_BROADCAST_PROFILE_BASE64:?Missing broadcast extension profile}"
: "${RUNNER_TEMP:?Run this script on the hosted macOS build runner}"

signing_dir=$(mktemp -d "$RUNNER_TEMP/inkflow-signing.XXXXXX")
keychain="$signing_dir/signing.keychain-db"
keychain_password=$(openssl rand -hex 32)
cleanup() {
  security delete-keychain "$keychain" 2>/dev/null || true
  rm -rf -- "$signing_dir"
}
trap cleanup EXIT
printf '%s' "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$signing_dir/certificate.p12"
printf '%s' "$IOS_APP_PROFILE_BASE64" | base64 --decode > "$signing_dir/app.mobileprovision"
printf '%s' "$IOS_WIDGET_PROFILE_BASE64" | base64 --decode > "$signing_dir/widget.mobileprovision"
printf '%s' "$IOS_BROADCAST_PROFILE_BASE64" | base64 --decode > "$signing_dir/broadcast.mobileprovision"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_dir/certificate.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"
security cms -D -i "$signing_dir/app.mobileprovision" > "$signing_dir/app.plist"
security cms -D -i "$signing_dir/widget.mobileprovision" > "$signing_dir/widget.plist"
security cms -D -i "$signing_dir/broadcast.mobileprovision" > "$signing_dir/broadcast.plist"
python3 scripts/prepare-signing.py "$signing_dir"
source "$signing_dir/build.env"
profiles="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profiles"
cp "$signing_dir/app.mobileprovision" "$profiles/$APP_PROFILE_UUID.mobileprovision"
cp "$signing_dir/widget.mobileprovision" "$profiles/$WIDGET_PROFILE_UUID.mobileprovision"
cp "$signing_dir/broadcast.mobileprovision" "$profiles/$BROADCAST_PROFILE_UUID.mobileprovision"

xcodebuild -project InkFlow.xcodeproj -scheme InkFlow -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/InkFlow.xcarchive \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" INKFLOW_BUNDLE_ID="$INKFLOW_BUNDLE_ID" \
  APP_PROFILE_UUID="$APP_PROFILE_UUID" WIDGET_PROFILE_UUID="$WIDGET_PROFILE_UUID" \
  BROADCAST_PROFILE_UUID="$BROADCAST_PROFILE_UUID" \
  INKFLOW_RELAY_GROUP="$INKFLOW_RELAY_GROUP" INKFLOW_APNS_ENVIRONMENT=production \
  INKFLOW_APP_ENTITLEMENTS=App/Relay.entitlements \
  INKFLOW_BROADCAST_ENTITLEMENTS=Broadcast/Relay.entitlements \
  archive | tee build/archive.log
xcodebuild -exportArchive -archivePath build/InkFlow.xcarchive \
  -exportOptionsPlist "$signing_dir/ExportOptions.plist" -exportPath build/export
rm -f -- "$profiles/$APP_PROFILE_UUID.mobileprovision" "$profiles/$WIDGET_PROFILE_UUID.mobileprovision" "$profiles/$BROADCAST_PROFILE_UUID.mobileprovision"

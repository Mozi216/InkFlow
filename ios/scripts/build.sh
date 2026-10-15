#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS targets require macOS and Xcode 27. Use the prepared GitHub Actions workflow.' >&2
  exit 1
fi
mkdir -p build
xcodebuild -version | tee build/environment.log
sdk=$(xcrun --sdk iphoneos --show-sdk-version)
if [[ "${sdk%%.*}" -lt 27 ]]; then
  echo 'The installed iOS SDK is older than 27.' >&2
  exit 1
fi
swift test --package-path InkFlowCore 2>&1 | tee build/core-tests.log
xcodegen generate --spec project.yml
xcodebuild -project InkFlow.xcodeproj -scheme InkFlow -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build | tee build/simulator-build.log
xcodebuild -project InkFlow.xcodeproj -scheme InkFlow -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/Device \
  CODE_SIGNING_ALLOWED=NO build | tee build/device-build.log
mkdir -p build/unsigned/Payload
ditto build/Device/Build/Products/Release-iphoneos/InkFlow.app build/unsigned/Payload/InkFlow.app
cd build/unsigned
ditto -c -k --keepParent Payload InkFlow-unsigned.ipa
echo 'InkFlow-unsigned.ipa is NOT installable until signed for the destination device.'

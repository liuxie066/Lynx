#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ${1:-} == --swiftpm && $# == 1 ]]; then
  # Local fallback when full Xcode is not ready. No asset-catalog compiler is required.
  swift build --build-system native --product Lynx --arch arm64
  lynx_bin_dir=$(swift build --build-system native --arch arm64 --show-bin-path)
  lynx_app=build/Lynx.app
  mkdir -p "$lynx_app/Contents/MacOS" "$lynx_app/Contents/Resources"
  cp "$lynx_bin_dir/Lynx" "$lynx_app/Contents/MacOS/Lynx"
  cp macOS/Info.plist "$lynx_app/Contents/Info.plist"
  cp LICENSE ThirdPartyNotices.md "$lynx_app/Contents/Resources/"
  cp macOS/Lynx.icns "$lynx_app/Contents/Resources/Lynx.icns"
  for appearance in Light Dark; do
    cp "macOS/Assets.xcassets/BrandMark$appearance.imageset/mark.png" "$lynx_app/Contents/Resources/BrandMark$appearance.png"
  done
  codesign --force --sign - "$lynx_app"
  printf '%s\n' "Built $lynx_app (local ad-hoc signature; not a distribution build)."
elif [[ $# == 0 ]]; then
  # DEVELOPER_DIR may point to Xcode on any disk; no global xcode-select change is made.
  xcodebuild -project Lynx.xcodeproj -scheme Lynx -configuration Debug \
    -derivedDataPath build/Xcode -destination 'platform=macOS,arch=arm64' build
  printf '%s\n' 'Built build/Xcode/Build/Products/Debug/Lynx.app'
else
  printf '%s\n' 'Usage: bash scripts/build-app.sh [--swiftpm]' >&2
  exit 2
fi

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
python3 Scripts/check-content.py
xcodebuild -project Transcriber.xcodeproj -scheme Transcriber -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages build "$@"
package_dir=$(mktemp -d "$PWD/build/package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
ditto build/DerivedData/Build/Products/Release/Transcriber.app "$package_dir/Transcriber.app"
codesign --verify --deep --strict "$package_dir/Transcriber.app"
python3 Scripts/check-content.py "$package_dir/Transcriber.app"
ditto -c -k --sequesterRsrc --keepParent "$package_dir/Transcriber.app" "$package_dir/Transcriber-macOS.zip"
(
    cd "$package_dir"
    shasum -a 256 Transcriber-macOS.zip > SHA256SUMS
)
mkdir -p build/Release
rm -rf build/Release/Transcriber.app
mv "$package_dir/Transcriber.app" build/Release/
mv "$package_dir/Transcriber-macOS.zip" "$package_dir/SHA256SUMS" build/Release/
python3 Scripts/source-digest.py > build/Release/SOURCE-SHA256
echo "Local Release app: $PWD/build/Release/Transcriber.app"

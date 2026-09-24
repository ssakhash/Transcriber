#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
swift build --disable-sandbox --scratch-path build/swift-package --cache-path build/package-cache
mkdir -p build
test_dir=$(mktemp -d "$PWD/build/storage-check.XXXXXX")
mkdir "$test_dir/mount"
hdiutil create -size 16m -fs HFS+ -volname TranscriberStorageTest "$test_dir/storage.dmg"
hdiutil attach -nobrowse -mountpoint "$test_dir/mount" "$test_dir/storage.dmg"
trap 'hdiutil detach "$test_dir/mount"' EXIT
build/swift-package/debug/MediaProbe storage "$test_dir/mount"

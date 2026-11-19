#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export CLANG_MODULE_CACHE_PATH=/tmp/swift-cache
mkdir -p "$CLANG_MODULE_CACHE_PATH"

echo "=================================================="
echo "      Running Pre-Commit Test & Build Suite       "
echo "=================================================="

# 1. Run Core Swift Package Tests
echo "--> [1/2] Running ReelsCreatorCore unit tests..."
CLANG_MODULE_CACHE_PATH=/tmp/swift-cache swift test --disable-sandbox --package-path ReelsCreatorCore --scratch-path /tmp/reelscreatorcore-build

# 2. Verify Xcode Build
echo "--> [2/2] Verifying iOS target build..."
xcodebuild -scheme reels-creator -destination 'generic/platform=iOS' -derivedDataPath /tmp/DerivedData CODE_SIGNING_ALLOWED=NO build > /tmp/xcodebuild_precommit.log 2>&1 || {
    echo "❌ Xcode build failed! Build log:"
    cat /tmp/xcodebuild_precommit.log
    rm -rf /tmp/DerivedData /tmp/xcodebuild_precommit.log
    exit 1
}
rm -rf /tmp/DerivedData /tmp/xcodebuild_precommit.log

echo "=================================================="
echo "✅ All tests and build checks passed successfully!"
echo "=================================================="

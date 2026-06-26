#!/bin/bash
# Build SlideShow for iPad and open in Finder
set -e
cd "$(dirname "$0")"
rm -rf /tmp/slideshow-build
xcodebuild -project SlideShow.xcodeproj -scheme SlideShow -sdk iphoneos -configuration Release -derivedDataPath /tmp/slideshow-build build ONLY_ACTIVE_ARCH=NO
open /tmp/slideshow-build/Build/Products/Release-iphoneos/
echo ""
echo "✅ 构建完成。在 Xcode → Devices → + 选择 SlideShow.app 安装。"

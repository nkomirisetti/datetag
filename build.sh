#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project DateTag/DateTag.xcodeproj -scheme DateTag -configuration Release build
echo ""
echo "Built. Look in ~/Library/Developer/Xcode/DerivedData/ for DateTag.app under Build/Products/Release/"

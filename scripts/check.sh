#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test
xcodebuild -project Inkflow.xcodeproj -scheme Inkflow -destination 'generic/platform=iOS' -derivedDataPath build-device CODE_SIGNING_ALLOWED=NO build

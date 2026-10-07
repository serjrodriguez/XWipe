#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=XWipe.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/XWipe $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>XWipe</string>
<key>CFBundleIdentifier</key><string>dev.local.xwipe</string>
<key>CFBundleExecutable</key><string>XWipe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --sign - $APP
echo "Listo: $PWD/$APP"

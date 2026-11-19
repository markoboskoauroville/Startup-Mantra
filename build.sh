#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p build
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' app/App.swift)
APP="build/Startup (Mantra).app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -o "$APP/Contents/MacOS/Startup (Mantra)" app/*.swift -framework AppKit -framework SwiftUI -framework ServiceManagement
cp Info.plist "$APP/Contents/Info.plist"
sed -i '' "s/<string>1<\/string>/<string>$V<\/string>/g" "$APP/Contents/Info.plist" 2>/dev/null || sed -i "s/<string>1<\/string>/<string>$V<\/string>/g" "$APP/Contents/Info.plist"
codesign --force -s "${SIGN:-Mantra Apps}" "$APP"
echo "built $APP (v$V)"
if [ "${NO_INSTALL:-0}" = "1" ]; then
  echo "not installed (NO_INSTALL=1)"
  exit 0
fi

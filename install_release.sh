#!/usr/bin/env bash
# Update the app on the connected phone IN PLACE (keeps the login and saved data). Do not use `flutter install`:
# it removes the old app first.
cd "$(dirname "$0")"
ADB="${ANDROID_HOME:-$LOCALAPPDATA/Android/sdk}/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB="adb"
"$ADB" install -r -d build/app/outputs/flutter-apk/app-release.apk

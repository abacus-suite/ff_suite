#!/usr/bin/env bash
# Release APK with Google's in-app map: the key lives in maps_key.txt (not committed).
cd "$(dirname "$0")"
KEY=$(cat maps_key.txt 2>/dev/null)
if [ -z "$KEY" ]; then
  echo "maps_key.txt is missing: building without Google's in-app map (the free map is used)."
  flutter build apk --release
else
  flutter build apk --release --android-project-arg=MAPS_API_KEY="$KEY" --dart-define=MAPS_BUILD_KEY=1
fi

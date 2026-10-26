#!/usr/bin/env bash
# Run on the Mac: builds the iOS app. The Google map key lives in ios/Secrets.xcconfig (not committed): MAPS_API_KEY=...
cd "$(dirname "$0")"
flutter pub get
(cd ios && pod install --repo-update)
if grep -q "MAPS_API_KEY=." ios/Secrets.xcconfig 2>/dev/null; then
  flutter build ipa --release --dart-define=MAPS_BUILD_KEY=1 "$@"
else
  echo "ios/Secrets.xcconfig has no key: building with the free map."
  flutter build ipa --release "$@"
fi

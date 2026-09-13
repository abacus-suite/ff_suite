# Field Force – Flutter app (Android)

One app for field officers and managers. Talks to the Odoo 19 `ff_mobile_api` module.

## Features (v0.1)
- Login with Odoo user (token stored encrypted, 90 days)
- Punch in / out with GPS + front-camera selfie, fake-GPS blocking
- Background location tracking while punched in (foreground service notification), offline queue, auto upload
- GPS on/off compliance events
- Monthly attendance calendar, attendance correction requests
- Managers: team live list + map, route replay per day, approvals

## First-time setup (one time)
1. Install Flutter (stable) and Android Studio (Android SDK + an emulator or USB phone).
2. Generate the Android platform folder (lib/ and pubspec.yaml already exist):
   ```
   flutter create . --platforms=android --org com.fieldforce --project-name field_force_app
   ```
3. Add these permissions inside `<manifest>` in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
   <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   <uses-permission android:name="android.permission.WAKE_LOCK"/>
   <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
   <uses-permission android:name="android.permission.CAMERA"/>
   ```
4. `flutter pub get` (if a package version is rejected: `flutter pub upgrade --major-versions`).

## Run / build
```
flutter run --dart-define=BASE_URL=https://<your-odoo-sh-url>
flutter build apk --release --dart-define=BASE_URL=https://<your-odoo-sh-url>
```
The server URL can also be changed on the login screen ("Server settings").

## Notes
- Maps use OpenStreetMap tiles — fine for a small team; switch to a paid tile provider for heavy use.
- On Xiaomi / Oppo / Vivo / Realme phones, users must also allow "Autostart" and set battery to "No restrictions" or tracking may stop.

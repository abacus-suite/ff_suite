# Aixolo – field app (Flutter, Android)

One app for field staff and their managers. It talks to the Aixolo modules on
Odoo 19 (`ff_mobile_api` and friends) — see `odoo_addons/README.md` in the
Odoo repository.

Package: `com.aixomind.aixolo` · Flutter stable · Dart 3.

## What the app does

**Every employee**
- Log in with the app login the office gives (token kept encrypted on the phone).
- **Home**: greeting and photo, check-in / check-out for the day, today's route summary,
  sales chart, quick actions, monthly **targets**, open **tasks**, leave / expense /
  allowance status, distance travelled, last visited customers.
- **Attendance**: GPS + selfie punch, fake-GPS blocking, phone-clock check, monthly
  calendar, correction requests.
- **Background tracking** while on duty; GPS-off warning; compliance events.
- **Customers**: nearby / all list and map, add a customer (route fills the city),
  customer page with **balance** (open and overdue invoices), **history** (visits,
  orders or demands, payments) and **edit** (details, move the pin).
- **Visits**: check-in with onsite / offsite decision, visit steps, stock count, forms,
  check-out with outcome and photos. Work at a customer (order/demand, payment, return)
  needs a check-in there, and a check-in needs the day's attendance.
- **Orders or demands** (company setting), **payment collection** and deposits,
  **returns & damaged goods** with photos, **expenses**, **travel allowance**,
  **time off**, **tasks** (start, finish with note and photo).
- **Reports**: 12 reports for a date range, list or table view, Excel download.
- **Notifications** inbox; **Profile** with photo; **More** menu.

**Managers** (anyone with a team in Odoo) also get: team live map and day timeline,
reports for any team member or the whole team, approvals (corrections, customers,
expenses, allowances, leave, returns), giving tasks.

## Offline
The app is built for dead zones.
- While online it saves the working day on the phone every 30 minutes (customers,
  route, products, forms, visit steps, balances…) and every screen it opens.
- Offline, screens show the saved copy, and **every action** (punch, check-in/out,
  demand, payment, stock count, steps, forms, expense, leave, return, approvals…) is
  queued with the time it really happened.
- The queue is sent oldest first as soon as there is network. The server remembers
  the answer to each request, so nothing is ever created twice.
- An orange strip shows you are offline; **Profile › sync line** opens the Sync screen
  (waiting / refused items, retry, discard, refresh the offline copy).

Code: `lib/core/outbox.dart` (queue), `offline_queue.dart` (SQLite), `api_client.dart`
(read cache), `local_state.dart` (what was done offline), `warm_up.dart` (pre-load).

## Project layout
```
lib/
  core/        API client, auth, storage, offline queue, tracker, photos, security guard
  features/    one folder per area (home, clients, visits, orders, collections, returns,
               tasks, reports, attendance, leaves, expenses, approvals, team, more, shell)
  widgets/     shared UI (home kit, charts, map, avatar, sync status)
```

## Build and install
```bash
flutter pub get
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
The server address is set on the login screen (**Server settings**) and remembered.

A release build needs a signing key (`android/key.properties` + keystore — never
committed) and `flutter build apk --release` or `flutter build appbundle`.

## Tests
```bash
flutter analyze
flutter test
```

## Settings that change the app (Odoo › Aixolo › Configuration › Settings)
Field timezone · selfie on punch · fake GPS · geofence radius and blocking · visit lock
and steps · stock count · payment collection · order flow (direct / demand) · idle
logout hours · allowed phone clock difference · Google Maps key.

## Phone notes
- Location must be **Allow all the time** for tracking.
- On Xiaomi / Oppo / Vivo / Realme: allow **Autostart** and set battery to
  **No restrictions**, or Android stops tracking.
- Without a Google Maps key the maps use OpenStreetMap.

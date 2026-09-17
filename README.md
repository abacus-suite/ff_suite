# Field Force Suite (Odoo 19) 

Field sales force management on Odoo 19 (Odoo.sh), with the Field Force Flutter
app (repository `ff_suite`).

## Modules
| Module | Purpose |
|---|---|
| `ff_base` | Teams, designations, devices, groups (Officer / Manager / Admin), settings, field timezone, reference numbering |
| `ff_tracking` | GPS pings, live status, inactive / no-signal flags, daily distance, compliance log |
| `ff_attendance` | Selfie + GPS punch (online or queued offline), shifts, late / half-day, calendar, corrections |
| `ff_clients` | Field customers, categories, approval of new customers, districts |
| `ff_visits` | Check-in / check-out, geofence, **onsite / offsite**, outcomes, offline flag |
| `ff_visit_steps` | Guided visit steps, stock count |
| `ff_beat` | Routes, route plans, planning from the app |
| `ff_orders` | Sale orders from the app, PTS / PTR / MRP and margins |
| `ff_demand` | Demand flow: outlet demands consolidated into distributor quotations |
| `ff_collections` | Payment collection (cash, online, cheque, PDC), deposits to office |
| `ff_expenses`, `ff_allowance` | Expense claims, distance-based travel allowance |
| `ff_approvals` | Approval chains (first / second approver) and notifications |
| `ff_leaves` | Time off from the app (Odoo Time Off) |
| `ff_leaves_approvals` | Time off through the approval chain when a flow is set *(auto-install)* |
| `ff_forms` | Custom forms |
| `ff_attribution*` | Field employee stamped on sales, CRM, invoices |
| `ff_live_map` | Google Maps live map, geocoding, map usage and cost |
| `ff_dashboard` | **Field Force Panel**: dashboard, live location + timeline, employees and org chart, attendance, leaves, expenses, orders, visits, demands, collections, targets — with Excel export |
| `ff_app_reports` | Reports in the app (own / team, date range, list / table, Excel) *(auto-install)* |
| `ff_targets` | Monthly visit / customer / sales / collection targets and achievement |
| `ff_tasks` | Tasks given to field staff, finished with note and photo |
| `ff_returns` | Returns and damaged / expired stock, approval, credit note |
| `ff_alerts` | Manager alerts (not moving, no signal, GPS off, offsite, fake GPS, clock changes) and daily / weekly email digest |
| `ff_mobile_api` | REST API `/api/v1/*` for the app, request receipts (every write safe to repeat) |

Install `ff_dashboard`, `ff_targets`, `ff_tasks`, `ff_returns` and `ff_alerts`; they
pull in the rest. Add `ff_demand`, `ff_collections`, `ff_forms` as the company needs.

## Setup after install
1. **Field Force › Configuration › Settings**: field timezone (then *Set it on everyone
   still on UTC*), tracking, selfie, geofence, order flow, payment collection,
   app security, manager alerts, email summary, Google Maps key.
2. Google Cloud: enable **Maps JavaScript API**, **Map Tiles API** and **Geocoding API**
   for the key.
3. For each field employee: app login, **Manager**, **Field Team**, **Field Shift**, data access.
4. Approval flows (Field Force › Configuration) for expenses, allowances and time off if two
   signatures are needed.
5. Outgoing mail server, for the email summary.

## API conventions
- Every response: `{"ok": true, "data": ...}` or `{"ok": false, "error": {"code", "message"}}`.
- `Authorization: Bearer <token>` on every call except login.
- **Writes carry a `uuid`.** The server stores the answer per uuid for 30 days and
  replays it if the same request comes again (header `X-Replayed: 1`).
- **Offline work carries `at`** (ISO UTC, when it really happened): records keep that
  time, rules are checked at that moment, anything older than 7 days is refused.
- Punches and check-ins sent live carry `device_time`; a phone clock further off than
  the setting is refused (`clock_skew`) and logged as time tampering.

Main groups of endpoints: `auth`, `me` (+ photo), `tracking`, `attendance`, `clients`
(+ history, balance, update), `visits` (+ steps, check-out by uuid), `beat` /
`route-plan`, `products`, `orders` / `demands`, `collections` / `deposits`, `returns`,
`expenses`, `allowances`, `leaves`, `tasks`, `targets`, `reports` (+ Excel download),
`team` (live, timeline), `approvals`, `notifications`.

## Tests
Tagged `ff`; Odoo.sh runs them on every build. Locally:
`odoo-bin -d test -i ff_dashboard,ff_targets,ff_tasks,ff_returns,ff_alerts --test-tags ff --stop-after-init`.

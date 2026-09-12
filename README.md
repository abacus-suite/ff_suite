# Field Force Suite (Odoo 19)  
 
Field sales force management for Odoo 19 (Odoo.sh) with a companion Flutter Android app.

## Modules (Phase 1)
| Module | Purpose |
|---|---|
| `ff_base` | Teams, designations, devices, security groups (Officer / Manager / Admin), settings |
| `ff_tracking` | GPS pings, live status, inactive / no-signal alerts, daily distance, compliance log |
| `ff_attendance` | Selfie + GPS punch, shifts, late / half-day marks, monthly calendar, regularisation approvals |
| `ff_mobile_api` | REST API `/api/v1/*` for the mobile app (bearer token auth) |

Install `ff_mobile_api` — it pulls in the others.

## Setup after install
1. Settings → Field Force: check tracking & selfie options.
2. Field Force → Configuration → Shifts: create shifts.
3. For each field employee: link a **user**, set **Manager**, **Field Team**, **Field Shift**, **Timezone**.
4. Give users the group *Field Force: Officer* (field staff) or *Field Force: Manager* (team leads).

## API quick reference
All responses: `{"ok": true, "data": ...}` or `{"ok": false, "error": {"code", "message"}}`.

| Method | Path | Notes |
|---|---|---|
| POST | `/api/v1/auth/login` | `{login, password, device_uid, device_name?, os_version?, app_version?, fcm_token?}` → `token` (90 days) |
| POST | `/api/v1/auth/logout` | `{device_uid}` revokes the token |
| GET | `/api/v1/me` | profile, roles, shift, app settings |
| POST | `/api/v1/device/register` | refresh push token / app version |
| POST | `/api/v1/tracking/pings` | `{pings: [{uuid, ts, lat, lng, accuracy, speed, battery, charging, gps_on, mock}]}` (≤500, idempotent on uuid) |
| POST | `/api/v1/tracking/compliance` | `{events: [{uuid, ts, type, detail}]}` |
| GET | `/api/v1/attendance/status` | today's punches |
| POST | `/api/v1/attendance/punch-in` / `punch-out` | `{lat, lng, accuracy, mock, address, selfie(base64), battery}` |
| GET | `/api/v1/attendance/month?year=&month=` | calendar with day status |
| GET/POST | `/api/v1/attendance/regularisations` | list / request correction |
| GET | `/api/v1/team/live` | manager: team live status |
| GET | `/api/v1/team/<employee_id>/timeline?date=` | manager: route replay |
| GET | `/api/v1/approvals` | manager: pending approvals |
| POST | `/api/v1/approvals/regularisation/<id>/approve\|reject` | manager decision |

Send `Authorization: Bearer <token>` on every call except login.

## Tests 
Tagged `ff`; Odoo.sh runs them on every build. Locally: `odoo-bin -d test -i ff_mobile_api --test-tags ff --stop-after-init`.

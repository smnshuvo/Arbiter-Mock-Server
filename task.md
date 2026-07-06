# Arbiter UI Revamp — Task Board

Source design: Claude Design project **"Mock server live activities UI"** (`20250bb0-…`), file `Arbiter Revamp.dc.html`.
Design screens: **Servers Home**, **Server Detail** (Endpoints / Logs / Settings tabs, HTTP + FTP variants), **New Server**, **Endpoint Editor**, plus a **Desktop** layout.

Visual language: warm off-white surfaces, orange accent `#F4541F`, Hanken Grotesk + JetBrains Mono, dotted background, soft shadows, glow/pulse animation. Applied app-wide via `AppColors` tokens + `monoTextStyle()` in `lib/core/theme/app_theme_data.dart`.

## Standing decisions
- **Themes:** keep both light and dark (palette tokenized into each); do not hardcode the design's light-only colors.
- **Interception:** the global real-time interception control lives in **Settings** (not Home). Per-server interception is shown as a read-only chip.
- **Stats (Network/Disk):** static placeholders until a metrics source exists.
- **FTP:** `Profile.type` (http/ftp) exists and drives the type chip; the actual FTP server is a separate backend task.

---

## ✅ Completed
- **Theme foundation** — `AppColors` tokens + `monoTextStyle()`; light/dark `ThemeData` on accent `#F4541F`; fonts via `google_fonts`.
- **Profile.type** — `enum ServerType { http, ftp }` on `Profile`/`ProfileModel`; `type` column, DB migration v3→v4 (default `http`).
- **Servers Home** — per-profile server-card list (status dot, name, type chip, elevated Run/Stop, URL, endpoint-count chip, `intercepting` chip), running summary, static stats strip, header (theme toggle + Logs + Settings), "＋ New server".
- **Interception → Settings** — toggle + mode dropdown moved to `SettingsScreen`.
- Card tap switches active profile → opens Endpoints; per-card Run uses stored settings with free-port fallback.

Remaining verification for the above: run the app end-to-end (start/stop, multi-profile, theme switch, interception).

---

## Roadmap (remaining pages)

### 1. Server Detail screen — HTTP  ⏳
A per-server screen opened from a Home card, replacing today's "tap card → Endpoints" shortcut.
- Header: back button, server name, `localhost:port`, status chip.
- Bottom nav: **Endpoints / Logs / Settings** tabs.
- Endpoints tab: run + URL card (copy, start/stop, request/error/endpoint counts), Interceptor (auto pass-through) card with scope toggle (all vs specific) + base URL, searchable endpoint list with method/status/mode/conditional/delay chips.
- **Depends on:** per-profile request/error counters (new plumbing); reuse existing endpoint list/CRUD.
- **Conflicts/notes:** today Endpoints & Logs are global screens keyed to the *active* profile. This screen makes them per-server — decide whether to switch the active profile on open (current behavior) or scope queries by an explicit `profileId` argument. Request/error counts don't exist yet.

### 2. Server Detail screen — FTP  ⏳
FTP variant of the detail screen.
- Run + URL card (`ftp://localhost:port`).
- Credentials (user / pass / root), Options (passive mode, read-only), Files-served list.
- **Depends on:** FTP server backend (task 8) and an FTP-specific settings model on `Profile`.
- **Conflicts/notes:** none of this data model exists yet; blocked until FTP lands.

### 3. New Server screen  ⏳
Dedicated create/configure flow (design has a full screen; today it's the `_StartProfileSheet` bottom sheet).
- Name, **type selector (HTTP / FTP)**, port, and type-specific options (pass-through for HTTP, credentials for FTP).
- **Depends on:** `Profile.type` (done); FTP options depend on task 8.
- **Conflicts/notes:** decide whether to promote the bottom sheet to a full screen or keep the sheet. Creating a profile currently defaults `type=http`; wire the selector through `CreateProfileEvent`.

### 4. Endpoint Editor redesign  ⏳
Restyle + extend `EndpointFormScreen` to the design.
- Method dropdown + path, **Match type** (exact / wildcard / regex — already in `MatchType`), **Mode** (Mock / Code-exec / Pass-through).
- Mock: status + delay steppers, response body with **Code** (JSON + highlight + format) and **Form** (tree editor) views, conditional responses.
- **Depends on:** Code-exec mode (task 5) for the third mode.
- **Conflicts/notes:** current model has Mock + Pass-through only and `LogType { mock, passThrough }`; the Form tree editor and JSON highlighting are new UI. Conditional mocks already exist (`ConditionalMatchType`).

### 5. Code execution mode  ⏳ (new feature)
Endpoint mode that runs a JS handler to build the response.
- Handler editor, request context, sandboxed execution, output/error surfacing.
- **Depends on:** a JS runtime/eval decision (e.g. `flutter_js`); new endpoint `mode` value + storage; server hot-path integration in `http_server_service.dart`.
- **Conflicts/notes:** largest new backend piece; security/sandboxing and desktop/mobile runtime support need evaluation. Referenced by `production_page_settings_parser/` screenshots.

### 6. Logs screen redesign  ⏳
Restyle `LogsScreen` to the design.
- Filter chips (method/type), compact rows (method, path, status, type, time, ms), tap to expand pretty-printed body.
- **Depends on:** nothing new; reuse `LogBloc`. Real-time logs already tracked separately.
- **Conflicts/notes:** keep existing filter capabilities; per-server scoping mirrors task 1.

### 7. Settings (per-server) + global Settings restyle  ⏳
- Per-server Settings tab (in detail): port (locked while running), auto pass-through + base URL, export configuration, delete server.
- Global `SettingsScreen`: restyle to the new language (already hosts interception, notifications, overlay).
- **Conflicts/notes:** export/import exists in the endpoint repository; "delete server" = delete profile (guard the `default` profile).

### 8. FTP server backend  ⏳ (new feature)
Actual FTP server behind the type chip / FTP detail screen.
- FTP listener, passive mode, read-only, credentials, served-files root; lifecycle wired into `ServerManager`/`ServerBloc` alongside the HTTP server.
- **Depends on:** an FTP server package decision; per-platform support (desktop vs mobile).
- **Conflicts/notes:** `ServerManager` currently assumes HTTP (`shelf`). Needs a per-type start path.

### 9. Desktop layout  ⏳
Design has a Phone/Desktop toggle with a desktop-optimized layout (master-detail, wider surfaces).
- **Depends on:** the phone screens above stabilizing first.
- **Conflicts/notes:** responsive/adaptive layout work; lower priority than mobile.

### 10. Real Network / Disk metrics  ⏳
Replace the Home stats-strip placeholders with live throughput + disk usage.
- **Depends on:** per-server request accounting (task 1) and a disk-usage source.
- **Conflicts/notes:** no data source today; purely additive once counters exist.

---

## Suggested order
1 (Server Detail HTTP) → 4 (Editor) → 6 (Logs) → 7 (Settings) → 8 (FTP backend) → 2 (FTP detail) → 3 (New Server) → 5 (Code-exec) → 10 (metrics) → 9 (Desktop).

# Tasks

# Home Screen Revamp — Feasibility & Work Scope

Source design: `Arbiter Revamp.dc.html` (Claude Design project "Mock server live activities UI", id `20250bb0-…`).
Scope requested: **revamp the Home screen only.**

> The design file also contains a Server-Detail screen (Endpoints/Logs/Settings tabs + bottom nav), an Endpoint Editor (Mock / Code-exec / Pass-through), and Desktop layouts. Those are **out of scope** here and referenced only where Home navigates into them.

## 1. What the design's Home ("Servers") screen contains
A single scrolling screen (`vServers`):
1. **Header** — animated Arbiter icon, "Arbiter" / "mock servers", settings gear.
2. **Big title** "Servers" + running summary (e.g. "2 of 3 running").
3. **Stats strip** — Network card (`MB/s`, ▲up/▼down) + Disk card (used/total GB + progress bar).
4. **Server cards** (one per profile): pulsing status dot, name, **type chip (HTTP/FTP)**, inline **Run/Stop toggle**, `localhost:port` URL, chips row (status, endpoint count, optional interception chip, optional error chip); tap → Server Detail.
5. **"＋ New server"** dashed button.

Visual language: light theme only, warm off-white cards (`#FFFCFA`), orange accent (`#F4541F`), Hanken Grotesk + JetBrains Mono, dotted background, glow/pulse animations.

## 2. Mapping to the current Home screen
Current `home_screen.dart`: single/multi server status card + global Port card + global Real-time Interception card + "Manage Endpoints"/"View Logs" buttons; AppBar has settings + light/dark theme switch; `_StartProfileSheet` collects profile/port/device-IP/auto-pass-through on start.

| Design element | Current app | Feasibility |
| --- | --- | --- |
| One card per profile | Profiles exist (`Profile`, `ProfileBloc`, `MultiServerRunning`) | ✅ Good fit |
| Inline Run/Stop per card | `StartProfileEvent`/`StopProfileEvent` exist | ✅ (start currently needs a sheet for port/pass-through) |
| Endpoint count per card | Endpoints are **global**, not per-profile | ⚠️ Needs per-profile counting |
| Request/error chips | No live per-profile counters | ⚠️ New metrics |
| Interception chip per card | Interception is **global** | ⚠️ Conflict (§3.1) |
| Type chip HTTP/FTP | No `Profile.type`; **FTP not implemented** | ⛔ New (branch: `ui-revamp-and-ftp-addition`) |
| Network + Disk stats | No data source | ⛔ New / must mock or drop |
| Light-only warm theme | App supports light **and** dark (`ThemeCubit`) | ⚠️ Conflict (§3.3) |

## 3. Conflicts with current features
1. **Real-time Interception has no place on the new Home.** It's currently a global toggle+mode dropdown on Home. The design's home has none; its per-card "interception chip" is read-only, and its detail-screen "Interceptor" card is actually *auto-pass-through* (a different feature). **Must decide where the interception control lives.**
2. **Global port field disappears from Home** — design sets port per-server in the (out-of-scope) detail Settings. Recommend keeping `_StartProfileSheet` for New-server/start so port/device-IP/pass-through stay reachable.
3. **Dark mode** — design is single warm light palette with hardcoded orange. App supports dark via `ThemeCubit`. Decide: keep dark (derive palette into both), go light-only, or style light now.
4. **Per-profile metrics don't exist** — endpoint counts, request/error counts, network/disk throughput have no backing data (endpoints/logs are global). Real numbers need new plumbing; otherwise hide or placeholder.
5. **FTP + server type** — type chip presumes `Profile.type` and a working FTP server, neither exists yet. Home renders a type chip once FTP lands; until then all servers are HTTP.

## 4. Feasibility summary
- **Directly feasible:** profile-driven server cards, inline run/stop, running summary, "New server" via existing start sheet, header/settings, visual restyle.
- **Needs new plumbing:** per-profile endpoint count, per-profile request/error counters.
- **Blocked on other work/decisions:** Network/Disk stats (no source), HTTP/FTP chip (FTP not built), interception placement, dark-mode strategy.

**Recommended "home only" MVP:** restyle to the design; one card per profile with status + inline run/stop + endpoint count + running summary + "New server"; keep the existing start bottom sheet; **defer** the stats strip and FTP chip; resolve interception placement + dark mode per the questions.

## 5. Decisions (resolved)
1. **Interception → move to Settings.** Remove the global interception toggle/mode from Home; Home shows only a read-only per-server interception chip. Add the toggle + mode dropdown to `SettingsScreen`.
2. **Stats strip → static placeholder.** Render Network + Disk cards matching the design with placeholder/zeroed values; wire real data later.
3. **Dark mode → keep both themes.** Adapt the warm palette + orange accent into both light and dark via `ThemeCubit`; keep the AppBar theme switch (or relocate it). Do **not** hardcode the design's light-only colors.
4. **FTP chip → include.** Add a `type` (HTTP/FTP) concept to `Profile` and render the type chip on cards, coordinating with the FTP work on branch `ui-revamp-and-ftp-addition`. Endpoint count per card is in; live request/error counters remain deferred (placeholder or hidden) unless trivial.

## 6. Work breakdown
1. ✅ **Theme foundation** (done) — added `AppColors` tokens + `monoTextStyle()` helper; light/dark `ThemeData` seeded on accent `#F4541F`, Hanken Grotesk body + JetBrains Mono via `google_fonts: ^6.2.1`; Home color literals routed to theme tokens.
2. ✅ **Profile.type** (done) — `enum ServerType { http, ftp }` + `type` field on `Profile`/`ProfileModel`; `type` column with DB migration **v3 → v4**, default `http`. `profile_model.g.dart` regenerated.
3. ✅ **Home restructure** (done) — rebuilt `home_screen.dart` body: in-body header (icon + Arbiter/mock servers + theme toggle + Logs + Settings), "Servers" title + running summary, static stats strip, one server card per profile (status dot, name, type chip, inline Run/Stop, URL, endpoint-count chip, `intercepting` chip when interception is on), and a "＋ New server" button. All lifecycle/overlay/interception-dialog/permission logic preserved.
4. ✅ **Per-profile endpoint count** (done) — `_loadEndpointCounts` queries `EndpointRepository.getAllEndpoints(profileId:)` per profile into a map, refreshed on `ProfileLoaded` and on return from the endpoints screen; rendered as the card's endpoint chip.
5. ✅ **Start flow** (done) — `_StartProfileSheet` kept and driven by "＋ New server"; per-card Run starts directly from the profile's stored settings, picking a free port if the preferred one is taken.
6. ✅ **Move interception controls** (done) — interception toggle + mode dropdown + info box moved to `SettingsScreen` (`_buildInterceptionCard`); removed from Home. Home still hosts the live intercept **dialog** + overlay sync.
7. ✅ **Wire card tap** (done) — tapping a card switches the active profile and opens the existing Endpoints screen (which follows the active profile); global Logs reachable from the header.
8. ⏳ **Verify** (pending) — `flutter analyze` passes with 0 errors/warnings. Still to do: run the app and confirm start/stop, multi-profile, theme switch, and interception behavior end-to-end.

Out of scope: Server-Detail tabbed screen, Endpoint Editor redesign (Mock/Code-exec/Pass-through), Desktop layout, real network/disk metrics, actual FTP server implementation (chip only).

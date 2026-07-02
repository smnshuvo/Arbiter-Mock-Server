# Local File Server — Feature Plan

A Wi-Fi file server built into the app. The user picks a folder, the app starts
a local HTTP server, and any device on the same network can browse and stream
files through a browser.

---

## Stack & Integration

The app is Flutter. The file server lives entirely in native Android code and is
exposed to Flutter via a **MethodChannel**. iOS and macOS support is planned for
a later phase.

```
Flutter UI
    │  MethodChannel
    ▼
Android (Kotlin)
  ├── FileServerService       (Foreground Service — keeps server alive)
  ├── FileServer              (NanoHTTPD — serves HTTP)
  ├── LibraryScanner          (MediaMetadataRetriever — thumbnails & metadata)
  ├── LibraryDatabase         (SQLite — stores metadata & thumbnail paths)
  └── SAF                     (Storage Access Framework — folder access)
```

**Dependencies (Android)**
- `org.nanohttpd:nanohttpd` — embedded HTTP server
- `androidx.documentfile:documentfile` — SAF file navigation
- `MediaMetadataRetriever` — built into Android, no dependency needed
- `SQLiteOpenHelper` — built into Android, no dependency needed

---

## Phase 1 — Server Foundation

**Goal:** Start and stop a working HTTP server from Flutter.

- Add NanoHTTPD and DocumentFile dependencies to `android/app/build.gradle`
- Create `FileServer.kt` extending NanoHTTPD
- Create `FileServerService.kt` as a Foreground Service
    - Displays a persistent notification showing the local URL while running
    - Declared in `AndroidManifest.xml` with `foregroundServiceType="dataSync"`
- Create a `MethodChannel` in `MainActivity.kt` with these methods:
    - `startServer(port, rootUri)` — starts the service
    - `stopServer()` — stops the service
    - `getLocalIp()` — returns the device's current Wi-Fi IP
- Register required permissions in `AndroidManifest.xml`:
    - `INTERNET`
    - `FOREGROUND_SERVICE`
    - `FOREGROUND_SERVICE_DATA_SYNC`

---

## Phase 2 — Folder Picker

**Goal:** Let the user choose any folder to share, with access that survives
app restarts.

- Trigger Android's `ACTION_OPEN_DOCUMENT_TREE` from Flutter via the
  MethodChannel (or use an existing Flutter SAF plugin)
- On folder selected, call `contentResolver.takePersistableUriPermission`
  with `FLAG_GRANT_READ_URI_PERMISSION` — this is essential; without it
  the URI breaks after a reboot
- Pass the persisted URI to `FileServerService` when starting the server
- Store the last used URI in SharedPreferences so the user does not have to
  re-pick on every launch

---

## Phase 3 — Directory Listing (Browser UI)

**Goal:** Any browser on the same Wi-Fi can browse the shared folder.

The server responds to `GET /` and `GET /any/sub/path/` with an HTML page.

**Page structure**
- Sticky header with a breadcrumb trail showing the current path
- Folder and file count summary line
- A table with columns: icon, name, size, last modified, actions
- Folders sorted before files, both alphabetically
- Clicking a folder row navigates into it
- A "Parent Directory" row at the top of every non-root page

**Icons** assigned by file extension in Kotlin, embedded as emoji in the HTML.

**Breadcrumbs** are built server-side from the current path segments, each
linking to its respective level.

---

## Phase 4 — File Serving with Range Request Support

**Goal:** Files download correctly and videos seek without re-downloading.

- Implement `Accept-Ranges: bytes` header on all file responses
- Read the `Range` header from the request if present
- Parse the byte range (start, end) and respond with `206 Partial Content`
  containing only those bytes
- Use a `LimitedInputStream` wrapper to avoid reading past the requested range
- Fall back to a full `200 OK` response if no Range header is present
- Guess MIME type from file extension in Kotlin; default to
  `application/octet-stream` for unknown types

This is required for browser video seeking to work. Without it, the `<video>`
tag loads but scrubbing is broken.

---

## Phase 5 — Action Buttons with Browser Compatibility Check

**Goal:** Each file row shows up to three action buttons. Play is only shown
if the browser can actually handle the format.

**Buttons**

| Button | Icon | Always shown | Condition |
|---|---|---|---|
| Play | ▶ | No | Browser confirms format support |
| Copy URL | 🔗 | Yes | All files |
| Download | ⬇ | Yes | All files |

Folders have no action buttons.

**How the compatibility check works**

- Server embeds the file's MIME type as a `data-mime` attribute on each play
  button in the HTML
- Play buttons are hidden by default via CSS (`display: none`)
- On page load, a small JavaScript block creates a hidden `<video>` element
  (never shown to the user) purely for probing
- It loops through all play buttons, reads the MIME from the data attribute,
  and calls `canPlayType(mime)` on the probe element
- If the result is `"probably"` or `"maybe"`, the play button is revealed;
  otherwise it stays hidden with no indication to the user
- This runs entirely in the browser — no extra round-trip to the server

**Copy URL behaviour**

- Copies the full `http://192.168.x.x:port/path/to/file` URL
- Uses the `navigator.clipboard` API with a textarea fallback for browsers
  that block clipboard access over plain HTTP (local IP URLs are not
  considered localhost by most browsers)
- Button briefly shows a tick `✓` then reverts to the link icon

---

## Phase 6 — Player Page

**Goal:** Tapping ▶ opens a clean in-browser video or audio player.

- Server handles `GET /player?v=/path/to/file.mp4`
- Returns a minimal HTML page with a full-screen `<video>` element pointed at
  the file path
- The `<video>` tag gets two `<source>` entries (MP4 and WebM) to maximise
  compatibility
- Page includes a back button (browser history) and a download link
- Audio files use an `<audio>` element on the same page template

---

## Phase 7 — Library Scan & Metadata

**Goal:** Build a database of media files with metadata so the library grid
loads instantly without scanning the filesystem on every request.

**When scanning runs**
- Automatically when the user picks a folder for the first time
- Manually via a refresh button in the Flutter UI and on the library page
- Incrementally — only processes files not already in the database; skips
  files whose last-modified timestamp has not changed

**What the scanner does per video file**
- Opens the file with `MediaMetadataRetriever`
- Extracts: duration, title (from metadata or filename as fallback), width,
  height, MIME type
- Generates a thumbnail and saves it to the app's private cache directory
- Inserts or updates a row in SQLite with all of the above

**What the scanner ignores**
- Non-media files — these stay in the file browser only, not the library grid
- Audio files — included in the library but use a generic music note
  placeholder instead of a video frame thumbnail

**SQLite table: `media_items`**

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | Auto-increment |
| `file_path` | TEXT UNIQUE | Full SAF URI string |
| `title` | TEXT | From metadata or filename |
| `duration_ms` | INTEGER | Milliseconds |
| `width` | INTEGER | Video resolution width |
| `height` | INTEGER | Video resolution height |
| `mime_type` | TEXT | e.g. `video/mp4` |
| `thumbnail_path` | TEXT | Absolute path in cache dir |
| `last_modified` | INTEGER | For change detection |
| `added_at` | INTEGER | Unix timestamp |

**Threading** — scanning runs entirely on a background thread via a Kotlin
coroutine. The Foreground Service notification updates to show scan progress
(e.g. "Scanning — 24 of 80 files"). The Flutter UI is notified via
EventChannel when the scan completes.

---

## Phase 8 — Thumbnail Generation & Library Grid

**Goal:** The browser shows a Jellyfin-style video grid with thumbnails,
titles, and durations. Clicking a card opens the player.

**Thumbnail generation**
- Uses `MediaMetadataRetriever.getFrameAtTime()` at 10% of the video's total
  duration — avoids black opening frames on most content
- Frame is compressed to JPEG at 85% quality and saved to the app's private
  cache directory under a filename derived from the file's URI hash
- If extraction fails (corrupted file, unsupported codec), a fallback
  placeholder image is used instead — the video is still listed
- Thumbnails are generated once and reused; regenerated only if the source
  file's last-modified timestamp changes

**Thumbnail serving**
- Dedicated server route: `GET /thumb?id=<media_id>`
- Server reads the JPEG path from SQLite by ID, opens the file, and returns
  it with `image/jpeg` MIME type
- Returns a generic placeholder image response if the thumbnail file is
  missing or the ID is not found

**Library grid page — `GET /library`**
- Reads all rows from `media_items` ordered by `added_at` descending
- Builds an HTML page with a CSS grid layout — no JavaScript framework,
  pure HTML and CSS served from the app
- Each card contains:
    - Thumbnail image loaded from `/thumb?id=<id>`
    - Video title below the thumbnail
    - Duration overlaid in the bottom-right corner of the thumbnail
    - Resolution badge (720p, 1080p, 4K) in the top-right corner
    - Clicking the card navigates to `/player?v=<file_path>`
- Empty state message if no media has been scanned yet, with a prompt to
  trigger a scan

**Navigation between views**
- The server root `GET /` serves the library grid by default
- A "Browse Files" link in the header switches to the file browser at
  `GET /files/`
- The file browser retains its existing table layout and action buttons

**Search (optional, can be added later)**
- A search input on the library page filters cards client-side with
  JavaScript — no server round-trip needed for small libraries
- For large libraries (500+ files), a `GET /library?q=term` server-side
  route queries SQLite with a `LIKE` clause instead

---

## Format Support Reference

| Format | Chrome | Firefox | Safari | Android Browser |
|---|---|---|---|---|
| MP4 (H.264) | ✅ | ✅ | ✅ | ✅ |
| WebM (VP8/VP9) | ✅ | ✅ | ⚠️ | ✅ |
| OGG / OGV | ✅ | ✅ | ❌ | ✅ |
| MKV | ❌ | ❌ | ❌ | ❌ |
| MOV | ⚠️ | ❌ | ✅ | ❌ |
| AVI | ❌ | ❌ | ❌ | ❌ |

MKV, AVI, and MOV will not play in any browser. The play button will simply
not appear for these — no error shown, just Copy URL and Download.

---

## Flutter UI Side

The Flutter layer only needs to:

- Call `getLocalIp()` and `startServer(port, uri)` via MethodChannel
- Display the resulting URL (`http://192.168.x.x:8080`) as copyable text and
  a QR code so nearby devices can connect quickly
- Provide Start / Stop toggle
- Show the currently shared folder name with a change button
- Optionally show a live request counter (the service can post this back via
  an EventChannel)

---

## Known Edge Cases

- **Reboot persistence** — the SAF URI must be persisted with
  `takePersistableUriPermission` or folder access is lost after a reboot
- **Server dies in background** — must run as a Foreground Service; a plain
  background service will be killed by Android in minutes
- **Same Wi-Fi only** — the server IP is a local address; it is unreachable
  over mobile data or different networks; communicate this clearly in the UI
- **Clipboard on HTTP** — `navigator.clipboard` requires HTTPS or localhost;
  local IPs over HTTP need the `execCommand` textarea fallback
- **Large files** — range requests handle streaming correctly, but very large
  files (10 GB+) should be tested; `ContentResolver.openInputStream` does not
  guarantee efficient seeking on all devices
- **Port conflicts** — let the user configure the port in settings in case
  8080 is already in use by another app or the mock server
- **Thumbnail extraction failure** — `MediaMetadataRetriever` can throw on
  corrupted or DRM-protected files; always wrap in try-catch and fall back to
  a placeholder image; never let one bad file crash the scan
- **Thumbnail cache size** — a large library generates many JPEGs; cap
  individual thumbnails at a reasonable resolution (e.g. 320×180) to keep
  cache size manageable; consider a cache eviction strategy for removed files
- **Scan on large libraries** — scanning hundreds of files with
  `MediaMetadataRetriever` is slow; always run off the main thread and show
  progress; allow the user to cancel and resume later
- **Stale thumbnails** — if a video file is replaced with a different one at
  the same path, the old thumbnail will be shown until a rescan; check
  last-modified timestamps to detect this

---

## Platform Roadmap

| Platform | Status | Notes |
|---|---|---|
| Android | 🔨 In scope now | NanoHTTPD + SAF |
| iOS | 🔜 Later | GCDWebServer or custom NWListener |
| macOS | 🔜 Later | Shares iOS approach via macOS Flutter target |

---

## Suggested Build Order

1. MethodChannel scaffold (start/stop/getIp) — verify Flutter can talk to
   native before writing server logic
2. NanoHTTPD running on a fixed folder — confirm it is reachable in a browser
3. SAF folder picker + persisted URI
4. Directory listing HTML at `/files/`
5. Range request file serving — test video seek before building the player
6. Action buttons + canPlayType check
7. SQLite schema and LibraryScanner — confirm metadata extraction works before
   building the UI on top of it
8. Thumbnail generation — verify JPEGs are produced and served correctly
9. Library grid page at `/` — thumbnails, titles, durations
10. Player page
11. Flutter UI polish (QR code, scan progress, request counter, port setting)

---

# Task Breakdown & Feasibility Analysis

Analysis grounded in the current Arbiter codebase. Ratings: 🟢 proven pattern
already exists here · 🟡 feasible, needs new work or a decision · 🔴 non-trivial
risk / unknowns.

## What already exists in this repo (reduces Phase 1 cost)
- **MethodChannel pattern** — `MainActivity.kt` already wires two channels
  (`…/foreground_service`, `…/overlay`) with a `when(call.method)` handler. Adding
  a `…/file_server` channel is a copy of an existing shape.
- **Foreground service pattern** — `ForegroundService.kt` + manifest `<service
  android:foregroundServiceType="dataSync"/>` already exist, and the required
  permissions are **already declared**: `INTERNET`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `ACCESS_NETWORK_STATE`.
  So Phase 1's permission/manifest work is ~90% done — only a second `<service>`
  entry is new.
- **Native → Dart callback** — the notification "stop" button already routes
  broadcast → `MethodChannel.invokeMethod` → Dart. Reuse for stop/scan events.
- **Kotlin package** `auravation.arbiter.mock_server`; new files land there.

**Correction to the plan:** this project's Gradle is **Kotlin DSL**
(`android/app/build.gradle.kts`), not `build.gradle`. Add NanoHTTPD/DocumentFile
in the `dependencies { }` block using `.kts` syntax.

## Tasks

### A. Native Android — server core
- **T1 · MethodChannel + service scaffold** 🟢 — new `…/file_server` channel
  (`startServer(port,rootUri)`, `stopServer()`, `getLocalIp()`); reuse
  MainActivity handler shape. Permissions already present.
- **T2 · `FileServer.kt` (NanoHTTPD) on a fixed folder** 🟢 — add dep, serve a
  hardcoded dir, confirm reachable in a browser.
- **T3 · `FileServerService.kt` foreground service** 🟢 — mirror
  `ForegroundService.kt`; **decision:** a *separate* service (recommended —
  independent lifecycle/notification) vs. multiplexing the existing one. Needs a
  distinct notification channel + id and a second manifest `<service>`.
- **T4 · SAF folder picker + persisted URI** 🟡 — `ACTION_OPEN_DOCUMENT_TREE`
  from native (or a Flutter SAF plugin) + `takePersistableUriPermission`
  (mandatory — reboot persistence) + last-URI in SharedPreferences.
- **T5 · Directory listing HTML `/files/`** 🟢 — breadcrumb, counts, sorted
  folders-first table, parent-dir row, emoji icons by extension.
- **T6 · Range-request file serving** 🟡 — `Accept-Ranges`, parse `Range`, `206`
  + `LimitedInputStream`, MIME by extension. Correctness-sensitive; watch the
  `ContentResolver.openInputStream` seek caveat on SAF URIs (edge case noted).
- **T7 · Action buttons + `canPlayType` probe + copy-URL** 🟢 — client-side JS;
  `execCommand` fallback for clipboard over plain-HTTP LAN IPs.
- **T8 · Player page `/player`** 🟢 — `<video>`/`<audio>` template, back +
  download.
- **T9 · Library scan + metadata (`media_items` SQLite)** 🔴 — biggest native
  piece: `MediaMetadataRetriever` on a coroutine, incremental (skip unchanged
  last-modified), progress via notification/EventChannel, cancel/resume. Slow and
  failure-prone on corrupt/DRM files — must never crash the scan.
- **T10 · Thumbnail generation + `/thumb`** 🟡 — `getFrameAtTime(10%)`, JPEG@85%
  to cache, hash-named, regen on mtime change, placeholder on failure, size cap
  (~320×180) + eviction for removed files.
- **T11 · Library grid `/` + search** 🟢 — CSS grid, duration/resolution badges;
  client-side filter, optional `?q=` SQLite `LIKE` for large libraries.
- **T12 · EventChannel** 🟡 — scan progress + live request counter native → Dart
  (new but standard; broadcast pattern already proven).

### B. Flutter integration
- **T13 · Dart `FileServerService` (MethodChannel wrapper)** 🟢 — mirror
  `lib/core/services/foreground_service.dart` / `overlay_service.dart`; no-op on
  non-Android.
- **T14 · Flutter UI** 🟡 — start/stop, shared-folder name + change, copyable URL,
  **QR code** (new dep, e.g. `qr_flutter`), request counter (EventChannel), port
  setting. Fits the revamp visual language.

### C. Integration decisions with Arbiter (resolve before building UI)
- **Server model** 🟡 — the mock server is a `Profile` with *endpoints*; the file
  server has a *shared folder + media DB* and no endpoints. **Recommend: do NOT
  model it as a mock `Profile`.** Represent it as its own server type/section (its
  own state + persistence). In the revamped server-list Home it can appear as a
  distinct card type (e.g. `ServerType`… `file`), Android-only.
- **Two server architectures** 🟢 (intentional) — mock = Dart `shelf` in-process;
  file = native NanoHTTPD. Keep separate; don't try to unify.
- **Port coexistence** 🟡 — file server must not collide with a running mock
  server (plan's port edge case). Share the free-port logic conceptually; expose a
  configurable port.
- **Persistence** 🟢 — keep the native `media_items` SQLite + SharedPreferences
  separate from the app's Dart `sqflite` DB (endpoints/logs/profiles). Two DBs is
  correct here, not a smell.
- **Platform gating** 🟡 — mock server is cross-platform (Dart); this file server
  is **Android-only** for now. The UI must gate/hide it on iOS/macOS/Linux/Windows
  and communicate "same Wi-Fi only".

## Top risks (feasibility flags)
- 🔴 **Library scan/thumbnails (T9/T10)** — performance + robustness on large or
  corrupt libraries; the make-or-break for a good UX. De-risk early with a real
  folder of mixed media.
- 🟡 **SAF range streaming (T6)** — seeking efficiency of SAF input streams for
  10 GB+ files varies by device; test video scrubbing on real hardware.
- 🟡 **SAF permission persistence (T4)** — miss `takePersistableUriPermission`
  and access breaks on reboot.
- 🟡 **Two foreground services** — notification channel/id collisions, and Android
  16+ FGS runtime limits; verify both can run concurrently.
- 🟢 **Scaffolding (T1–T3, T13)** — low risk; proven patterns already in-repo.

## Verdict
**Feasible.** It's a self-contained Android-native module bridged by MethodChannel
— a pattern this app already uses three times. Phase 1 is largely pre-built
(permissions + FGS + channel scaffolding exist). Real effort/risk concentrates in
the media pipeline (scan, thumbnails, range streaming). The main architectural
decision is to keep it **separate from the mock-server `Profile`/endpoint model**
and surface it as its own Android-only server type in the revamped UI. iOS/macOS
remain a later phase (native server rewrite required).
# Wi-Fi File Server — Technical Brief

How the Android Wi-Fi file server streams video to browsers (especially TV browsers),
and everything built so far to make that work. The feature lives entirely in native
Kotlin (`android/app/src/main/kotlin/auravation/arbiter/mock_server/`), bridged to a
single Flutter screen; it is fully separate from the app's mock-server profiles.

---

## 1. Architecture at a glance

```
┌─ Flutter (Dart) ──────────────────────────────────────────────┐
│ file_server_screen.dart   UI: folder, port, start/stop, QR,   │
│                           uploads toggle, speed/total, scan   │
│ file_server_service.dart  MethodChannel + EventChannel bridge │
└───────────────┬───────────────────────────────────────────────┘
                │ auravation.arbiter.mock_server/file_server(_events)
┌─ Native (Kotlin) ─────────┴───────────────────────────────────┐
│ MainActivity        channel handler, SAF folder picker        │
│ FileServerService   foreground service, owns server lifecycle │
│ FileServer          NanoHTTPD — all routes, HTML/JS/CSS       │
│ LibraryScanner      incremental media scan (coroutine)        │
│ LibraryDatabase     SQLite media_items (file_server_library.db)│
│ Thumbnailer         poster JPEGs + storyboard sprite sheets   │
│ FileTypes           MIME map, icons, formatting               │
│ FileServerEvents    scan progress / request count → Dart      │
└───────────────────────────────────────────────────────────────┘
```

- **Folder access is SAF**: the user picks a folder with `ACTION_OPEN_DOCUMENT_TREE`;
  the grant is persisted (read+write) so it survives reboots. All file access goes
  through `ContentResolver` with document IDs — never raw paths.
- **Server**: embedded NanoHTTPD 2.3.1 on a user-chosen port (default 8080), kept
  alive by its own foreground service (notification id 2001), independent of the
  mock-server's foreground service.

### HTTP routes (`FileServer.kt`)

| Route | Purpose |
|---|---|
| `/`, `/library` | Media library grid (scanned videos, thumbnails, search) |
| `/files/…` | TV-navigable file browser for **all** file types |
| `/raw/<path>` | File bytes with HTTP Range support (`?dl=1` forces download) |
| `/media?id=` | Same, but addressed by library DB id |
| `/player?id=` / `?v=` | Custom video/audio player page |
| `/thumb?id=` | Poster thumbnail (SVG placeholder on miss) |
| `/storyboard?id=` | Seek-preview sprite sheet |
| `/subs?id=&n=` / `?v=&n=` | Sidecar subtitle as WebVTT |
| `POST /upload?dir=` | Multipart upload into the viewed folder (opt-in) |

---

## 2. How video streaming actually works

There is no transcoding and no special protocol — it is plain progressive HTTP with
**Range requests**, which is all a browser `<video>` element needs:

1. The player page emits `<video><source src='/media?id=N' type='video/mp4'></video>`
   (the MIME captured at scan time, since extensions can lie or be absent).
2. The browser probes the file (a `HEAD`/initial `GET`), reads the container index
   (e.g. the MP4 `moov` atom), and then requests only the byte windows it needs:
   `Range: bytes=123456-`.
3. The server answers `206 Partial Content` with `Content-Range: bytes start-end/total`
   and `Accept-Ranges: bytes`, streaming just that window.

Key implementation details in `serveDocument` / `openStreamAt`:

- **O(1) seeking into files.** SAF streams don't support random access, and
  `InputStream.skip()` on them literally reads and discards every preceding byte
  (deep seeks took seconds). Instead we open a `ParcelFileDescriptor`, wrap it in an
  `AutoCloseInputStream`, and call `FileChannel.position(start)` — a true constant-time
  seek. A skip-loop fallback covers providers with non-seekable descriptors.
- **`LimitedInputStream`** caps a range response at exactly `end - start + 1` bytes.
- **`parseRange`** supports `start-end`, open-ended `start-`, and suffix `-N` forms.
- **HEAD short-circuits** to headers-only (players probe before streaming).
- `?dl=1` switches `Content-Disposition` to `attachment` for downloads.
- **Why seeks still cost something:** each seek makes the browser abort its stream,
  open a new Range request, and re-buffer from the nearest keyframe over Wi-Fi. The
  server side is O(1); the re-buffer is inherent. That's what the deferred scrubbing
  below is for.

---

## 3. The player (TV-remote-first)

TV browsers don't expose native `<video controls>` to a D-pad, so the player page
ships its own controls in vanilla JS (`playerPage` / `playerScript` in `FileServer.kt`).

- **Control bar**: Back · Play/Pause · seek bar · time · ⚙ Settings · ⬇ Download.
  ↑/↓ move focus through controls, OK activates, controls auto-hide after 3s.
- **Key robustness**: every handler resolves keys from both `e.key` *and* numeric
  `e.keyCode` (37–40 arrows, 13 Enter, 8/27/461/10009 Back, 179 MediaPlayPause) —
  many TV remotes only send legacy keyCodes.
- **Seek bar** fills left→right and always shows *actual* playback (fill + round
  knob). It is itself focusable; ←/→ scrub only while it's focused.
- **Deferred (Netflix-style) scrubbing**: arrow presses never touch
  `media.currentTime`. They move a preview bubble + target tick; the real seek
  commits **once**, 600 ms after the last press (or immediately on OK). A burst of
  presses costs a single re-buffer instead of one per press. Scrub sessions are
  one-directional — the opposite arrow cancels instead of reversing.
- **Storyboard previews**: the bubble shows the actual frame at the target time,
  pulled from a pre-generated sprite sheet (`/storyboard?id=`) by shifting a CSS
  `background-position` — zero network traffic while scrubbing.
- **⚙ Settings menu** (D-pad navigable): Fullscreen toggle + subtitle selection
  (Off / each discovered track, ✓ on active), or "No subtitles found".
- **Subtitles**: sidecar `.srt`/`.vtt` files next to the video with the same base
  name (`movie.srt`, `movie.en.srt`) are discovered per page load, converted
  SRT→WebVTT on the fly (`WEBVTT` header + comma→dot timestamps), and injected as
  `<track>` elements. Works for both library items and Browse-Files playback.
- **Fullscreen** uses `requestFullscreen()` with webkit fallbacks.

The two grids (`/library`, `/files/`) share the same remote model: ←/→ move tile
focus (wrapping), the focused tile reveals View/Download, ↑ picks View, ↓ picks
Download, OK activates, Back goes up a level. Leading nav tiles cross-link the two
pages so everything is reachable without a mouse.

---

## 4. Media library, thumbnails, storyboards

`LibraryScanner` walks the shared tree on a background coroutine (`ScanController`),
extracting metadata per file with `MediaMetadataRetriever`:

- **Incremental**: unchanged `lastModified` → skipped (except a storyboard backfill
  pass for videos indexed before storyboards existed).
- **Never crashes**: every file is try/caught; corrupt/DRM files keep a
  filename-only row.
- **Poster thumbnail**: frame at 10% of duration, ≤320×180 JPEG q85, cached in
  `cache/media_thumbs/<uriHash>.jpg`.
- **Storyboard sprite**: ≤60 frames (one per ≥10 s), each 160×90, tiled 6-across
  into a single JPEG q70 (`<uriHash>_sb.jpg`, ~100–200 KB) — the same trickplay/BIF
  technique YouTube and Netflix use.
- Rows live in `media_items` (SQLite v2; storyboard columns added via migration).
  Upserts preserve row ids so `/media?id=` URLs stay valid across rescans.
- Progress streams to the Flutter screen over the EventChannel; deleted files are
  pruned and their cached images evicted.

---

## 5. Performance work

The first implementation used `DocumentFile`, where **every** property access
(name/size/isDirectory/…) is a separate ContentResolver IPC query — listings were
N+1 and slow. Replaced with:

- **One children query per directory** via
  `DocumentsContract.buildChildDocumentsUriUsingTree` with a 5-column projection
  (`listChildren` → `ChildDoc`).
- **Short-TTL caches (60 s)** for path→docId resolution, file docs, and media
  name/size (`TtlCache`) — a page view or seek burst hits these hard, and the TTL
  avoids stale-id bugs after renames.
- Root doc id computed once; stale-cache listings retry once after a cache clear.
- FD-based `channel.position()` seeking (section 2) removed the read-and-discard
  seek cost.

---

## 6. Uploads (opt-in) and traffic stats

- **Uploads** are gated by an app-side switch (off by default, persisted, flippable
  live via `FileServer.uploadsEnabled` — a `@Volatile` companion flag). When on,
  every `/files/` page shows a multi-file upload form posting to
  `POST /upload?dir=<path>`; NanoHTTPD buffers parts to temp files, then the server
  creates documents via `DocumentsContract.createDocument` and copies bytes in.
  Disabled → 403. The SAF picker now takes a **read+write** grant (folders picked
  before this need a one-time re-pick to become writable).
- **Traffic stats**: every byte served (files, ranges, thumbs, storyboards) flows
  through a `CountingInputStream` into a per-session `AtomicLong`; uploads count
  too. The Flutter screen polls `getTrafficStats` once per second and shows
  **current speed** (1-s delta) and **total transferred**; the total resets on
  server start.

---

## 7. Flutter surface

`FileServerScreen` (entry: Android-only card on `HomeScreen`) is self-contained
state, no BLoC: shared-folder card (pick/change), port field, uploads switch,
start/stop, QR + copyable URL, requests-served counter, speed/total card, and
library scan controls with live progress. `FileServerService` (Dart) no-ops on
non-Android platforms.

## 8. Change log (this branch)

| Commit | What |
|---|---|
| `c145ad3` | Full feature: NanoHTTPD server, SAF, Range streaming, library scan + thumbnails, player, TV D-pad UI, Flutter screen |
| `4a4c630` | Perf: single-query listings, TTL caches, O(1) FD seeking, HEAD short-circuit |
| `2d2cea1` | Storyboard seek previews, deferred scrubbing, seek-state clarity (fill/knob/tick, one-direction scrub), sidecar subtitles, gear menu |
| `da099c6` | Opt-in browser uploads + live speed/total-bandwidth stats |

### Known limitations

- Codec support is whatever the client browser can decode (e.g. MKV/HEVC may not
  play everywhere) — there is no transcoding.
- Subtitles: sidecar files only; embedded container tracks (and image-based subs
  like PGS) are not extracted.
- Desktop/remote uploads only make practical sense from mouse/touch browsers; the
  file-input control is awkward from a TV remote.
- Old shared-folder grants are read-only until re-picked once.

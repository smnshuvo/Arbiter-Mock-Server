# Media Encoding & On-the-Fly Transcoding — Feature Plan

Extends the Local File Server plan. Goal: every video in the library gets a
play button, regardless of container or codec. Files the browser cannot play
natively are converted — preferably live, while the user watches.

**Priority order:**
1. **Phase T0 — Embedded subtitles** (highest priority): the current player
   shows no subtitles even when they exist inside the file; fix this first
2. **On-the-fly transcoding (Jellyfin-style)**: pre-transcoding exists only
   as a fallback path for weak devices

---

## Phase T0 — Embedded Subtitles (Do This First)

**The problem:** browsers never display subtitle tracks embedded inside a
video file. Even for a Direct Play MP4, the `<video>` tag ignores embedded
subtitles entirely. The only thing a browser renders is an external WebVTT
file attached via a `<track>` element. So subtitles are always an
extract-and-serve job, regardless of playback tier.

**The two kinds of embedded subtitles — completely different problems**

| Kind | Formats | Where found | Strategy |
|---|---|---|---|
| **Text-based** | SRT, ASS/SSA, mov_text | Most MKVs, some MP4s | Extract → convert to WebVTT → serve |
| **Bitmap-based** | PGS (Blu-ray rips), VobSub (DVD rips) | Common in MKV movie rips | Cannot convert to text without OCR — burn into the video during transcode instead |

**T0.1 — Subtitle detection at scan time**

- Extend LibraryScanner: enumerate subtitle tracks per file with their
  index, codec, and language tag
- New table `subtitle_tracks`:

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK | |
| `media_id` | INTEGER FK | → `media_items` |
| `track_index` | INTEGER | Stream index inside the container |
| `codec` | TEXT | `srt`, `ass`, `mov_text`, `pgs`, `vobsub` |
| `language` | TEXT | ISO code from metadata, e.g. `en`, `bn` |
| `title` | TEXT | Track title if present (e.g. "Forced", "SDH") |
| `is_text` | INTEGER | 1 = convertible to WebVTT, 0 = bitmap |

- Also detect **sidecar subtitle files** in the same folder: `movie.srt`,
  `movie.en.srt` next to `movie.mkv` — treat them as additional tracks

**T0.2 — Extraction & conversion to WebVTT**

- Server route: `GET /subs/{media_id}/{track_index}.vtt`
- On first request, extract that track with FFmpeg and convert to WebVTT;
  cache the result in the app cache dir; subsequent requests serve the cache
- ASS/SSA styling (positioning, colors, karaoke effects) does not survive
  conversion to WebVTT — accept plain-text rendering for v1; note that
  heavily styled anime subs will lose formatting
- Sidecar SRT files go through the same conversion (SRT → WebVTT is nearly a
  find-and-replace: timestamps and a header)
- Character encoding: SRT files in the wild are often not UTF-8 (Windows-1252,
  regional encodings); detect and convert to UTF-8 or subtitles render as
  garbage

**T0.3 — Player integration**

- Player page queries `GET /subs/{media_id}/list` → JSON of available tracks
- One `<track kind="subtitles">` element per text track, labeled with
  language and title, `srclang` set from the language tag
- Default track selection: none on by default; remember the user's last
  chosen language in browser localStorage and auto-enable it next time
- The browser's native subtitle menu handles the on/off and track switching
  UI — no custom controls needed for v1
- **Works for all tiers:** Direct Play, Remux, and Transcode all use the same
  `<track>` mechanism — subtitles are served independently of the video
  stream, so T0 does not depend on the transcoding phases at all and ships
  before them

**T0.4 — Bitmap subtitles (PGS/VobSub)**

- Cannot become WebVTT without OCR (unreliable, heavy) — v1 strategy:
  - If the user enables a bitmap track, playback switches to the Transcode
    tier with the subtitle **burned into the video** (FFmpeg overlay filter)
  - Clearly label these tracks in the player menu ("burned-in") since
    enabling one forces a transcode and disables instant track switching
- If transcoding is not yet built when T0 ships, bitmap tracks are listed as
  unavailable with a tooltip — text tracks still work everywhere

**T0 definition of done**

- An MKV with embedded SRT shows a working subtitle menu in Chrome and the
  text renders in sync
- A sidecar `movie.srt` next to `movie.mp4` appears as a selectable track
- A non-UTF-8 SRT renders correctly
- Subtitle choice persists across sessions on the same browser

---

## The Three-Tier Playback Decision

Every playback request is routed through a decision made at scan time and
stored in the database:

```
Browser requests playback
        │
        ▼
┌─ Tier 1: DIRECT PLAY ────────────────────────────────┐
│ Container + codec browser-compatible (MP4/H.264/AAC) │
│ → Serve the file as-is with range requests           │
│ → Zero CPU cost                                      │
└──────────────┬───────────────────────────────────────┘
               │ not compatible
               ▼
┌─ Tier 2: REMUX ──────────────────────────────────────┐
│ Codec is fine (H.264/AAC) but container is not (MKV) │
│ → Rewrap packets into fMP4/HLS on the fly            │
│ → Near-zero CPU cost, no quality loss                │
└──────────────┬───────────────────────────────────────┘
               │ codec itself unsupported
               ▼
┌─ Tier 3: TRANSCODE ──────────────────────────────────┐
│ Codec unsupported (HEVC*, VP9-in-MKV, MPEG4, etc.)   │
│ → Decode and re-encode to H.264/AAC live             │
│ → Heavy: hardware codec, battery, thermal            │
└──────────────────────────────────────────────────────┘
```

*HEVC plays natively in Safari and some Chromium builds — the client-side
`canPlayType` check from Phase 5 decides per-browser, so the same file may be
Direct Play for one device and Transcode for another.

---

## Phase T1 — Codec Detection at Scan Time

**Goal:** Know each file's playback tier before anyone presses play.

- Extend the existing LibraryScanner: for every media file, use
  `MediaExtractor` to read track information — video codec, audio codec,
  container, bitrate, profile/level
- Store in new `media_items` columns:

| Column | Type | Notes |
|---|---|---|
| `video_codec` | TEXT | e.g. `h264`, `hevc`, `vp9`, `mpeg4` |
| `audio_codec` | TEXT | e.g. `aac`, `ac3`, `dts`, `opus` |
| `container` | TEXT | e.g. `mp4`, `mkv`, `avi` |
| `bitrate` | INTEGER | For transcode quality decisions |
| `playback_tier` | INTEGER | 1 = direct, 2 = remux, 3 = transcode (default assumption; final tier decided per-browser) |

- The library grid and player page read this to decide which URL to hand the
  `<video>` element: the raw file path (Tier 1) or the transcode endpoint
  (Tiers 2–3)
- Audio-only sidecar problem: a file can have H.264 video but DTS/AC3 audio
  the browser cannot decode — this is extremely common in MKVs. Track video
  and audio tiers separately; audio-only transcode (copy video, re-encode
  audio) is far cheaper than full transcode and should be its own sub-path

---

## Phase T2 — Streaming Protocol: HLS

**Goal:** Pick the delivery mechanism that makes live transcoding seekable.

**Why plain progressive MP4 does not work here:** a normal MP4 needs its
index (`moov` atom) finalized, which only happens when encoding finishes. A
browser cannot seek into a file that is still being written. This is the core
problem on-the-fly transcoding must solve.

**Decision: HLS (HTTP Live Streaming)** — the same approach Jellyfin uses.

- The transcoder produces short segments (4–6 seconds each) plus a playlist
  file (`.m3u8`) listing them
- The browser player fetches the playlist, then segments one by one
- New segments are appended to the playlist as they are encoded — the user
  watches while encoding continues
- **Seeking:** when the user jumps ahead, the player requests a segment that
  may not exist yet → the server kills the current transcode session and
  restarts encoding from the requested timestamp
- Segment format: fMP4 (fragmented MP4) segments rather than legacy MPEG-TS —
  better browser support and no extra remux step

**Server routes**

| Route | Purpose |
|---|---|
| `GET /stream/{id}/master.m3u8` | Playlist; starting this URL starts a transcode session |
| `GET /stream/{id}/seg{n}.m4s` | Individual encoded segment |
| `GET /stream/{id}/init.mp4` | fMP4 initialization segment |
| `DELETE /stream/{id}` | Client signals playback stopped — kill session |

**Browser side**

- Safari plays HLS natively via the `<video>` tag
- Chrome/Firefox/Edge need **hls.js** — a small JS library the player page
  loads from the app's own server (bundle it in assets; no CDN dependency,
  keeps the offline promise)
- The player page logic: if `playback_tier == 1` for this browser, use the
  direct file URL; otherwise use the HLS playlist URL

---

## Phase T3 — The Transcoding Engine

**Goal:** Choose and integrate the component that actually converts frames.

**Option A — Android native pipeline (MediaExtractor → MediaCodec → MediaMuxer)**

- Zero APK size cost, no licensing concerns
- Hardware-accelerated H.264 encoding is mandatory on every Android device
- Hardware HEVC/VP9 *decoding* is present on most devices from the last
  ~7 years
- Significant engineering: manual pipeline management, surface handling for
  decode→encode, audio resampling, A/V sync, per-device codec quirks
- Cannot handle exotic codecs the device lacks a decoder for (DTS audio is
  the big one — very few Android devices decode DTS in hardware)

**Option B — FFmpegKit (bundled FFmpeg)**

- Handles every container and codec that exists, including DTS/AC3 audio
- HLS segment output is a built-in one-liner of configuration
- Can still use the device's hardware encoder via MediaCodec integration
- Costs 20–30 MB APK size (use the `min-gpl` or a custom build with only
  needed codecs to shrink this)
- Licensing: use an LGPL build and dynamic linking to stay Play-compatible;
  avoid GPL components (libx264 → prefer the hardware MediaCodec encoder or
  openh264). Document the exact build variant chosen.
- Note: FFmpegKit's original maintainer retired the project in 2025 — plan to
  pin a specific version or use a maintained community fork; verify current
  state before committing

**Decision: Option B (FFmpegKit) for v1 of transcoding.**
The audio-codec problem alone (DTS/AC3 in MKVs) makes the native pipeline
insufficient for real-world files. Revisit a native fast-path later if APK
size becomes a problem.

---

## Phase T4 — Transcode Session Management

**Goal:** Transcoding is stateful and expensive — sessions must be tracked
and killed aggressively.

**Session lifecycle**

- A session starts when a browser first requests a `master.m3u8`
- One session per (file, client); identified by a session token in the
  playlist URL
- Each session owns: an FFmpeg process, a temp segment directory, a last-
  accessed timestamp
- **Idle kill:** if no segment has been requested for 30 seconds, kill the
  FFmpeg process and delete segments — the user closed the tab or paused
  long enough that resuming can simply restart the session
- **Seek handling:** segment requested beyond the encoded horizon → kill and
  restart FFmpeg with a start-time offset (`-ss`); already-encoded segments
  behind the horizon are served from disk
- **Concurrency cap:** hard limit of 1–2 simultaneous transcode sessions
  (configurable). Additional playback requests for Tier 3 files get a clear
  in-player message: "Another video is converting — try again shortly."
  Direct Play and Remux sessions are not counted against this cap.

**Storage**

- Segments live in the app's cache directory under `/transcode/{session}/`
- A rolling window: keep only the last N minutes of segments behind the
  playhead to bound disk usage on long movies
- All session directories purged on server stop and app start

**Thermal & battery**

- Register a thermal status listener; on `THERMAL_STATUS_SEVERE` or above,
  lower the encode resolution/bitrate for new segments, and surface a
  notification if a session must be killed
- Show an ongoing "Converting video…" line in the existing Foreground
  Service notification while any transcode session is active
- Setting: "Only transcode while charging" (off by default, discoverable)

---

## Phase T5 — Quality & Speed Settings

**Goal:** Sensible defaults, minimal knobs.

- Default target: H.264 High profile, AAC stereo, capped at the source
  resolution or 1080p (whichever is lower), CRF-equivalent quality preset
- Hardware encoder first (MediaCodec via FFmpeg), software fallback only if
  hardware initialization fails
- User-facing settings (Flutter side): max transcode resolution
  (720p / 1080p / original), transcode concurrency (1 / 2), only-while-
  charging toggle
- Audio-only transcode path (Phase T1's split): when video is H.264 but audio
  is DTS/AC3, copy the video stream untouched and re-encode audio only —
  10–20x cheaper than full transcode, and visually lossless

---

## Phase T6 — Pre-Transcoding (Fallback, Later)

Kept minimal since on-the-fly is the priority:

- Manual per-file action in the library UI: "Convert for browser playback"
- Runs the same FFmpeg pipeline but writes a complete MP4 next to the
  original (or into app storage if the SAF tree is read-only)
- Useful for: very old/slow devices, files watched repeatedly, and users who
  want zero battery drain during playback
- Converted files are re-scanned and become Tier 1 forever

---

## Player Page Changes

- Load hls.js from the app's own assets when the chosen source is HLS
- Tier badge in the player UI (Direct / Converted) — subtle, for debugging
  and user trust
- On player close/unload, fire the `DELETE /stream/{id}` beacon so sessions
  die immediately instead of waiting for the idle timeout
- Error state when the concurrency cap is hit, with a retry button

---

## Known Edge Cases & Risks

- **Seeking storms** — a user scrubbing rapidly can trigger many kill/restart
  cycles; debounce seeks server-side (ignore a new seek if one restarted
  <2 seconds ago)
- **DTS/AC3 audio in otherwise-playable files** — the most common real-world
  case; must hit the cheap audio-only path, not full transcode
- **Subtitle sync on transcode seek** — after a seek-restart of the encoder,
  segment timestamps must stay aligned with the independently served WebVTT
  timeline or subtitles drift; keep the HLS timeline anchored to source
  timestamps rather than restarting at zero
- **ASS styling loss** — heavily styled subtitles (anime typesetting) render
  as plain text after WebVTT conversion; known limitation, document it
- **HDR content** — HEVC HDR transcoded to H.264 SDR without tone mapping
  looks washed out; v1 accepts this with a known-issue note; tone-mapping is
  expensive and deferred
- **10-bit content** — many hardware decoders reject 10-bit H.264 ("Hi10P",
  common in anime rips); FFmpeg software decode handles it but slowly; cap
  these to 720p output by default
- **Device without hardware HEVC decode** — software decode of 4K HEVC will
  not keep up with realtime on most phones; detect and cap output resolution,
  or warn the user
- **APK size review** — FFmpegKit build must be trimmed to needed
  codecs/muxers only; verify final size before release
- **Licensing audit** — confirm the FFmpeg build is LGPL-only before Play
  submission; keep a record of the build configuration
- **Foreground service justification** — transcoding strengthens the case for
  `dataSync`/`mediaProcessing` foreground service type; on newer Android
  versions `mediaProcessing` (Android 15+) is the more accurate declared type
  for transcode work — decide per `targetSdkVersion`

---

## Suggested Build Order

1. **Subtitle track detection in LibraryScanner + `subtitle_tracks` table**
   — verify against MKVs with embedded SRT/ASS and sidecar files
2. **WebVTT extraction route with caching + encoding detection**
3. **Player `<track>` integration with track list endpoint** — T0 ships here,
   before any transcoding exists; text subtitles now work for all Direct
   Play files
4. Codec detection in LibraryScanner + new DB columns — verify tier
   classification against a real mixed folder (MP4s, MKVs, AVIs)
5. Integrate FFmpegKit; prove a one-shot file→HLS conversion works on-device
   (FFmpegKit also replaces whatever extraction method step 2 used, if a
   lighter interim method was chosen)
6. HLS session manager: start on playlist request, idle kill, temp dir
   lifecycle
7. Player page with hls.js from local assets; play a Tier 2 (remux) MKV
   end-to-end — remux first because it isolates protocol bugs from encoder
   bugs; confirm subtitles still work over HLS
8. Full Tier 3 transcode path with hardware encoder
9. Seek restart handling + seek debounce; verify subtitle sync after seek
10. Audio-only transcode fast path
11. Bitmap subtitle burn-in path (T0.4 completes here)
12. Concurrency cap, thermal listener, notification integration
13. Quality settings in Flutter UI
14. Pre-transcode manual action (Phase T6)

---

## Definition of Done (v1)

- An MKV with embedded SRT subtitles plays with a working, in-sync subtitle
  menu — for Direct Play, Remux, and Transcode paths alike
- Sidecar `.srt` files appear as selectable tracks
- An MKV with H.264/AC3 plays in Chrome with working seek (remux + audio
  transcode path)
- An AVI/MPEG4 file plays in Chrome with working seek (full transcode path)
- Subtitles remain in sync after seeking within a transcode session
- Closing the tab kills the FFmpeg process within seconds
- Two devices can Direct Play while one transcode session runs
- Battery and thermal behaviour verified with a 2-hour 1080p transcode on a
  mid-range device
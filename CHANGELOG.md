# Changelog

## Version 3.1.0 (Build 10)

**Interception**
• URL whitelist/blacklist filtering — scope live interception to matching URL patterns (wildcards supported), or exclude them, instead of pausing on every request

**Home screen**
• NETWORK and DISK cards now show real Wi-Fi File Server traffic instead of static placeholders: live speed and cumulative bytes while running, falling back to the last session's average speed and total once stopped

**Fixes**
• Floating overlay's header showed a placeholder "A" badge instead of the app icon

---

## Version 3.0.1 (Build 9)

The app is now **Arbiter File Server** — renamed across Android, iOS, macOS, Linux, and Windows.

**Phone as TV remote**
• Control the file-server web UI from your phone: D-pad, search typing, and playback keys pushed live to connected browsers (with a crisp native click on every press)
• Live playback sync — a real seekbar and volume slider in the app that track and control the video playing on the TV
• Landscape layout for the remote: D-pad on the left, playback controls on the right

**Player & media**
• MKV/TS files are now playable and fast-seekable — converted to MP4 on-device, with live progress shown in the player and a prompt before converting
• Custom subtitle picker (choose any subtitle file from the share) and resume-from-last-position
• Seek-engage mode for precise scrubbing; audio-drift fix for remuxed files
• New full-screen image viewer: open photos from the file browser, flip through the folder with remote arrows or keys, with counter and download
• File browser tiles now show real thumbnails for images and videos (generated lazily, cached)

**File server**
• Auto-stop after 1 hour of inactivity (optional) so the server doesn't run forever in the background
• Fixed: reopening the File Server screen while the server was running showed it as stopped — the screen now re-syncs with the live server (URL, port, request count, traffic stats)

---

## Version 3.0.0 (Build 8)

### 🎉 Major Feature: Wi-Fi File Server (Android)

Share a folder from your device over the local network — browse, stream, and manage it from any browser, with a UI built for TV remotes.

**Serving & browsing**
• Pick any folder (SAF) and serve it over HTTP on a chosen port, kept alive by its own foreground service with QR code and copyable URL in the app
• Arbiter File Server web UI: branded pages (app icon + favicon), media library grid with thumbnails, resolution/duration badges and search, plus a full file browser for every file type with View/Download actions
• Fully D-pad navigable from a TV remote — tile navigation, reachable search (opens the TV keyboard), works with both modern and legacy remote key codes

**Video player**
• Custom remote-friendly player (native controls are unreachable on TVs): play/pause, focusable seek bar with knob, fullscreen, download
• Netflix-style seeking — arrow presses scrub a preview bubble with real storyboard thumbnails; the video seeks once when you stop, instead of re-buffering per press
• Sidecar subtitle support (.srt/.vtt next to the video), selectable from a gear menu with on-the-fly SRT→WebVTT conversion

**Access & transfer**
• Optional login: anonymous by default, or require a username/password (HTTP Basic) — switchable live from the app
• Opt-in uploads: allow browsers on the network to add files to the shared folder (off by default)
• Live traffic stats in the app: current speed and total bytes transferred
• Fast on big folders: single-query directory listings, cached path resolution, and O(1) byte-range seeking for instant streaming

---

## Version 2.1.1 (Build 7)

• Fixed: Auto Pass-Through now binds to each profile individually — the URL and toggle are configured in the Start Server sheet, pre-filled from the profile's saved settings, and persisted to the database so the URL is remembered across restarts

---

## Version 2.1.0 (Build 6)

• Live log streaming — see requests in real time as they hit your mock server
• Batch create endpoints from logs — long-press logs, select multiple, create all at once
• Duplicate endpoint detection — prompts to update instead of silently failing
• Fixed: root path "/" matching, list reordering on toggle, and a crash on back navigation

---

## Version 2.0.0 - New Features Added

### 🎉 Major Features

#### 1. Conditional Mock Responses
Return different JSON responses based on request conditions:

**Query Parameter Matching:**
- Match based on URL query parameters
- Example: `?id=1` returns different data than `?id=2`
- Perfect for testing pagination, filtering, user profiles

**Body Field Matching:**
- Match based on JSON request body fields
- Example: Different responses based on `userId` or `orderType`
- Perfect for testing login flows, role-based responses

**Features:**
- Multiple conditions per endpoint
- Default fallback response
- Visual indicator showing condition count
- Easy-to-use configuration UI

#### 2. Auto Pass-Through Mode
Automatically forward unmatched requests to a global base URL:

**How it works:**
- Set a global base URL once
- Any request without a matching endpoint gets forwarded automatically
- Request path is preserved: `localhost:8080/api/users` → `{base_url}/api/users`

**Benefits:**
- No need to configure pass-through for every endpoint
- Perfect for hybrid testing (mock some, real API for others)
- Quick switch between development and production APIs
- Ideal for API migration testing

**Configuration:**
- Global toggle on home screen
- Configure base URL once
- Enable/disable anytime
- Works alongside existing endpoints

### 📊 Database Changes
- Added `conditionalMocksJson` field to store conditional mock rules
- Added `useConditionalMock` flag for endpoints
- Backward compatible with existing data

### 🎨 UI Improvements
- New "Auto Pass-Through" section on home screen
- Conditional mock configuration screen
- Visual indicators for conditional mocks on endpoint list
- Improved endpoint form with conditional mock toggle
- Better visual feedback for enabled features

### 🔧 Technical Changes
- Enhanced HTTP server to support conditional matching
- Added query parameter parsing
- Added request body field extraction
- Improved pass-through logic with auto-forwarding
- New use cases for server configuration
- Updated BLoC for new features

### 📝 Documentation
- Added comprehensive FEATURE_GUIDE.md
- Updated README.md with new examples
- Added troubleshooting section
- Included best practices

### 🐛 Bug Fixes
- Improved error handling in conditional mock parsing
- Fixed JSON parsing for nested body fields
- Better error messages for configuration issues

---

## Version 1.0.0 - Initial Release

### Features
- Local HTTP server
- Endpoint configuration with exact/wildcard/regex matching
- Mock responses with configurable delays
- Pass-through mode to forward requests
- Request logging with detailed information
- Advanced filtering and search
- Import/Export configurations
- Clean architecture implementation
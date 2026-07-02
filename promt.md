# Design Prompt — Arbiter File Server "TV Remote" UI

Copy everything below into Claude design.

---

Design a mobile **remote-control panel** for an existing Flutter Android app called **Arbiter File Server**.

## Product context

The app runs a Wi-Fi file server on the phone. Other devices on the network — most importantly a **TV browser** — open its web UI to browse a shared folder, view a media library grid, and watch videos in a custom player. The web UI is fully driven by D-pad-style logical keys: `up / down / left / right / ok / back`, plus play-pause. Today the user drives it with the TV's physical remote; we are adding the ability to drive it **from the phone itself**: buttons in the app send those same key events over the local network to the connected browser, so the phone becomes the remote.

The panel lives inside the app's existing **File Server screen** (it can be a section of that screen, a bottom sheet, or a dedicated full-screen "Remote" page reached from it — recommend and justify one).

## What the remote must contain

1. **D-pad**: up/down/left/right around a central **OK** button. This is the primary control — big, thumb-friendly, center of the layout.
2. **Back** button (browser back / exit player).
3. **Media row** for when a video is playing: play/pause, seek −10s, seek +10s. (Seek left/right double as D-pad left/right in the player, but explicit media buttons are clearer.)
4. **Text input affordance**: a small "type" action that opens the phone keyboard and sends text to the TV's focused search box (much nicer than typing with a TV remote).
5. **Connection status**: how many browsers are connected ("1 device listening", "No devices connected — open the URL on your TV"), with a subtle live indicator.
6. A compact reminder of the **server URL** (e.g. `http://192.168.0.12:8080`) so the user knows what to open on the TV.

## States to design

- **Server stopped**: the remote is disabled/dimmed with a clear call-to-action to start the server.
- **Server running, no clients**: remote visible but idle, with the "open this URL on your TV" hint prominent.
- **Server running, client connected**: remote fully active.
- **Button feedback**: pressed state + light haptic implied; keys can be held for repeat (e.g. holding → to keep moving focus).

## Visual language (match the existing app)

- Flutter, **Material 3**, phone portrait, supports **light and dark theme** (design dark first).
- Existing app style: near-black background in dark mode, content grouped in **rounded cards (~14px radius)** with hairline outlines, single blue **accent `#4F9DFF`**, green for "running" states, red for stop/destructive.
- The companion web UI (for tone reference) uses: bg `#0F1216`, card `#181D24`, text `#E7ECF2`, muted `#8A97A6`, accent `#4F9DFF`.
- Typography: system font, monospace for URLs/numbers.
- Brand: app icon + "Arbiter **File Server**" (accented second word).

## Interaction notes

- Latency is near-zero (LAN), so buttons should feel instant — no loading spinners on press.
- One-handed use is the norm: keep the D-pad in the lower two-thirds of the screen.
- Don't crowd it: the D-pad, back, and media row are 90% of usage; everything else is secondary.
- Consider a discreet "which device am I controlling?" affordance for the future multi-client case (one TV is the common case today — broadcast is fine).

## Deliverables

- High-fidelity mockups of the remote panel in its three states (stopped / no clients / connected), dark theme, 390×844 frame.
- The chosen placement (section vs. sheet vs. page) shown in context of a settings-style screen that already contains: shared-folder card, port field, "Allow uploads" toggle, "Require login" card, Start/Stop button, QR + URL card, requests/speed/total-transferred stats.
- Component spec: sizes, spacing, colors, pressed/disabled states for the D-pad and buttons.

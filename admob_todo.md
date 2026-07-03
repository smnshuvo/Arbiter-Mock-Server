# AdMob Integration TODO

## Setup
- [x] Branch `admob-integration` from `ui-revamp-and-ftp-addition`
- [x] Add `google_mobile_ads`; `ad_config.dart` (IDs placeholder → test); manifest/plist App IDs; init SDK in `main.dart`
- [x] `AdService` (interstitial hourly gates, rewarded 12h unlock) + `AdBanner` widget, registered in get_it
- [x] Bump Kotlin Gradle Plugin 1.8.22 → 2.1.0 (required by google_mobile_ads' webview_flutter transitive dep)

## Favicon
- [x] Serve `assets/favicon.ico` at `/favicon.ico`; `<link rel='icon'>` points at it

## Ads
- [x] Bottom banner on endpoint screen
- [x] Interstitial on Start Server (gate `ad_gate_start_server`, once/hour)
- [x] Interstitial on Open TV Remote (gate `ad_gate_open_remote`, once/hour)
- [x] Bottom banner on the remote (fixed bottomNavigationBar)

## Remote seekbar / volume (rewarded unlock)
- [x] Back-channel: player POSTs position/duration/volume to `/remote/state` → EventChannel → Dart
- [x] Remote locked seekbar (matches movie duration/position) + volume bar; rewarded ad → 12h unlock
- [x] Absolute seek + volume commands (`seek:`/`vol:` over the remote SSE channel)

## File server idle-stop
- [x] "Stop server if idle" toggle (default on) + native 1h idle watchdog + `stopped` event flips UI

## Player
- [x] Player click-to-pause/play (click `#media` → toggle)

## Verified
- Debug APK builds, installs, and runs with no crash.
- Mobile Ads SDK initializes; an interstitial AdActivity displayed & dismissed at runtime (test IDs).
- Remaining behavioral checks best done by hand: seekbar mirroring a real TV playback session,
  and the 1-hour idle auto-stop (temporarily lower `IDLE_TIMEOUT_MS` to test quickly).

## Notes
- Real AdMob App ID + ad unit IDs: paste into `lib/core/ads/ad_config.dart` (and the native
  App IDs in `AndroidManifest.xml` / iOS `Info.plist`). Until then, Google TEST ads are used.
- Interstitial gates are SEPARATE per trigger (Start Server vs Open Remote), each once/hour.
- Seekbar/volume unlock lasts 12 hours after watching a rewarded ad.

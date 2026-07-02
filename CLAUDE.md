    # CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Arbiter Mock Server** is a Flutter app (package: `arbiter_mock_server`) that runs a local HTTP server on-device to intercept, mock, and proxy network requests during development and testing. It targets Android, iOS, macOS, Linux, and Windows.

Flutter version is pinned via FVM: `3.35.5` (see `.fvmrc`). Use `fvm flutter` instead of `flutter` if FVM is active.

## Commands

```bash
# Install dependencies
flutter pub get

# Regenerate JSON serialization code (run after modifying any @JsonSerializable model)
flutter pub run build_runner build --delete-conflicting-outputs

# Run the app
flutter run

# Analyze (lint)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart
```

**Linux prerequisite**: `libsqlite3` and `libsqlite3-dev` packages must be installed.

**Windows release mode**: `sqlite3.dll` must be placed alongside the executable (debug bundles it automatically).

## Architecture

Clean Architecture with three layers — `domain` → `data` → `ui` — and strict unidirectional dependency flow.

### Domain layer (`lib/domain/`)
Pure Dart with no Flutter dependencies.
- **Entities**: `Endpoint`, `RequestLog`, `InterceptionRequest`, `InterceptionMode`, `Settings` — core business objects.
- **Repository interfaces**: abstract contracts that the data layer implements.
- **Use cases**: one class per operation (e.g., `StartServer`, `GetAllEndpoints`, `ModifyAndContinue`). Each use case is a callable class that takes a single repository argument and is injected via `get_it`.

### Data layer (`lib/data/`)
- **`database_helper.dart`**: SQLite singleton via `sqflite`. Uses `sqflite_common_ffi` on Linux/Windows (in-memory) and native `sqflite` on Android/iOS/macOS (persisted). Currently at schema version 2.
- **`http_server_service.dart`**: The core of the app. Built on `shelf`, it runs the local HTTP server. On each request it: (1) optionally intercepts the request via `InterceptionManager`, (2) matches the URL against cached `Endpoint` objects, (3) returns a mock response or proxies to a target URL, (4) optionally intercepts the response, (5) logs the result to SQLite.
- **`interception_manager.dart`**: Manages live request/response interception. Uses a `StreamController<InterceptionRequest>` to push pending intercepts to the UI, and a `Map<String, Completer>` to pause server processing until the user acts or the auto-timeout fires.
- **Models** (`endpoint_model.dart`, `request_log_model.dart`): JSON-serializable DTOs generated with `json_serializable`. After modifying these, re-run `build_runner`.
- **Repositories**: concrete implementations of domain interfaces.

### UI layer (`lib/ui/`)
- **State management**: `flutter_bloc`. Each feature area has its own BLoC (`ServerBloc`, `EndpointBloc`, `LogBloc`, `InterceptionBloc`, `SettingsBloc`). `ThemeCubit` is separate for light/dark theme.
- **Dependency injection**: `get_it` with a single `GetIt` instance (`sl`) wired in `lib/ui/bloc/dependency_container.dart`. BLoCs are `registerFactory`; everything else is `registerLazySingleton`. The `HttpServerService.onRequestReceived` callback is set in `setupRequestNotificationCallback()` after all singletons are ready — this avoids a circular initialization dependency.
- **Screens**: `HomeScreen` (server control + pass-through config), `EndpointScreen` + `EndpointFormScreen` (CRUD), `LogsScreen` + `LogFilterScreen`, `SettingsScreen`, `WelcomeScreen` (shown once on first launch via `SharedPreferences`).

### Android foreground service (`lib/core/services/foreground_service.dart`)
Communicates with native Android code over `MethodChannel('auravation.arbiter.mock_server/foreground_service')`. Keeps the server alive when the app is backgrounded. The `onStopServerRequested` static callback must be set by `HomeScreen` before the server is started. No-ops silently on non-Android platforms.

### Wi-Fi File Server (Android-only, native NanoHTTPD)
A second, fully separate server for sharing a user-picked folder over LAN. **Not** modelled as a mock `Profile` — it has no endpoints, its own SQLite DB, and its own foreground service. Lives entirely in native Kotlin, bridged to Dart.
- **Native Kotlin** (`android/app/src/main/kotlin/.../`): `FileServer.kt` (NanoHTTPD; routes `/`, `/library`, `/files/`, `/raw/`, `/media`, `/player`, `/thumb`, with HTTP Range support via `LimitedInputStream`), `FileServerService.kt` (foreground service, own channel `file_server_channel`/id `2001`), `FileTypes.kt` (MIME/icons/formatting), `LibraryDatabase.kt` (SQLite `media_items`, separate `file_server_library.db`), `LibraryScanner.kt` + `Thumbnailer.kt` + `ScanController.kt` (incremental coroutine scan via `MediaMetadataRetriever`, never crashes on bad files), `FileServerEvents.kt` (EventChannel emitter).
- **Channels**: `MethodChannel('.../file_server')` — `startServer(port,rootUri)`, `stopServer()`, `getLocalIp()`, `pickFolder()` (native SAF `ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`), `getSavedFolder()`, `scanLibrary()`, `cancelScan()`, `isScanning()`. `EventChannel('.../file_server_events')` streams scan progress + live request count.
- **Dart**: `lib/core/services/file_server_service.dart` (wrapper, no-ops off Android) + `lib/ui/screens/file_server_screen.dart` (self-contained state; start/stop, folder pick, port, copyable URL, QR via `qr_flutter`, request counter, scan progress). Entry is an Android-only card on `HomeScreen`.
- SAF root is a persisted tree URI; library items store full SAF document URIs and are served by DB id via `/media?id=`.
- **Phone-as-TV-remote**: `/remote/events` is an SSE stream; the app pushes logical keys/search text via `FileServer.pushRemote()` (MethodChannel `sendRemoteKey`/`sendRemoteText`), and pages consume them through the same handlers as D-pad keys (`window.__remoteKey`/`__remoteText`). UI: `lib/ui/screens/file_server_remote_screen.dart`.
- **NanoHTTPD gzip gotcha**: `HTTPSession.execute()` re-applies the gzip decision AFTER `serve()` returns, so per-response `setGzipEncoding(false)` is silently overwritten — override `useGzipWhenAccepted()` instead. SSE (`text/event-stream`) must never be gzipped: the compressor buffers the tiny events forever and they never reach the client. curl won't reproduce this (it doesn't send `Accept-Encoding: gzip`; browsers do).

## Key Design Decisions

- **Endpoint matching priority**: endpoints are checked in insertion order; the first match wins. Conditional mocks within an endpoint are also checked in order.
- **Desktop SQLite**: Linux and Windows use an in-memory database (data does not persist across restarts on those platforms). Only Android/iOS/macOS persist to disk.
- **`HttpServerService` endpoint cache**: endpoints are not read from the DB on every request. `onEndpointsNeeded()` triggers a reload into `_cachedEndpoints` via the DI container, keeping the hot path synchronous.
- **CORS**: all responses have permissive CORS headers added by middleware so the server can be used from browser-based dev apps.

## Must follow
- Learn from your mistakes, add these mistakes to this file so that you don't repeat
- If you learn a new context about this project add them here for your ease of work
- If you are not clear about anything ask question to clear before proceeding

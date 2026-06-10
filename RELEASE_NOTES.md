# Release Notes

## v2.1.0 (Build 6)

### New Features
- **Real-time log streaming** — logs appear live as requests hit the server. Tap the play/pause button in the Logs screen to toggle the stream.
- **Batch endpoint creation from logs** — long-press one or more log entries to enter selection mode, then tap "Create N Endpoints". Choose a target profile and default delay in the dialog. Duplicate patterns are skipped automatically.

### Improvements
- Log screen AppBar decluttered — Filter, Export, and Clear actions moved into the overflow menu; redundant reload button removed.
- Switching an endpoint on/off no longer changes its position in the list.
- Trying to create an endpoint with a pattern that already exists now prompts you to update the existing one instead of silently failing.

### Bug Fixes
- Requests to the root path `/` are now matched correctly.
- Batch-creating endpoints from logs no longer deletes existing endpoints in the profile first.
- Fixed a crash when navigating back from the Logs screen.

import 'package:flutter/material.dart';

/// In-app permission priming for the Android floating overlay.
///
/// Shown BEFORE the system "Display over other apps" prompt to explain the
/// feature in context (Google's recommended priming pattern). Styled with the
/// Arbiter Live Activity design language (dark card, mono labels, accent colours).
/// Returns `true` if the user chose to continue to the system permission prompt.
Future<bool> showOverlayPrimingSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _OverlayPrimingSheet(),
  );
  return result ?? false;
}

// Design tokens (Arbiter Live Activity - Android).
const _card = Color(0xFF1D2025);
const _inner = Color(0xFF15181D);
const _text = Color(0xFFE9EEF4);
const _path = Color(0xFFCDD6E2);
const _muted = Color(0xFF7A8595);
const _blue = Color(0xFF5FA0FF);
const _green = Color(0xFF3FD07A);
const _red = Color(0xFFFF6B6B);
const _accent = Color(0xFF3B82F6);
const _mono = 'monospace';

class _OverlayPrimingSheet extends StatelessWidget {
  const _OverlayPrimingSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Live preview of the floating surface.
          const _Preview(),
          const SizedBox(height: 20),

          const Text(
            'Floating overlay',
            style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Float a draggable live activity over your other apps so you can watch '
            'requests — and continue, edit, or drop intercepted ones — while testing '
            'in another app. Drag it anywhere; tap to expand the feed.',
            style: TextStyle(color: _path, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _inner,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.layers_outlined, color: _blue, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Next, Android will ask you to allow "Display over other apps" '
                    'for Arbiter. You can turn this off anytime in Settings.',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: _path,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small mock of the overlay: the collapsed bubble above the expanded feed.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF243A52), Color(0xFF1A2740)],
        ),
      ),
      child: Column(
        children: [
          // Collapsed bubble
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                const Text('GET', style: TextStyle(color: _blue, fontFamily: _mono, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                const Text('/v1/users', style: TextStyle(color: _text, fontFamily: _mono, fontSize: 12)),
                const SizedBox(width: 8),
                const Text('200', style: TextStyle(color: _green, fontFamily: _mono, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Expanded feed card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            decoration: BoxDecoration(
              color: _inner,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: const [
                _Row(method: 'GET', methodColor: _blue, path: '/v1/users', status: '200', statusColor: _green),
                _Row(method: 'POST', methodColor: _green, path: '/v1/orders', status: '201', statusColor: _green),
                _Row(method: 'DEL', methodColor: _red, path: '/v1/session', status: '401', statusColor: _red, last: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String method;
  final Color methodColor;
  final String path;
  final String status;
  final Color statusColor;
  final bool last;

  const _Row({
    required this.method,
    required this.methodColor,
    required this.path,
    required this.status,
    required this.statusColor,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(method, style: TextStyle(color: methodColor, fontFamily: _mono, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(path, style: const TextStyle(color: _path, fontFamily: _mono, fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
          Text(status, style: TextStyle(color: statusColor, fontFamily: _mono, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

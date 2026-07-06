import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ads/ad_banner.dart';
import '../../core/ads/ad_config.dart';
import '../../core/ads/ad_service.dart';
import '../../core/services/file_server_service.dart';
import '../../core/theme/app_theme_data.dart';
import '../bloc/dependency_container.dart';

/// Phone-as-remote for the file server's web UI: sends logical D-pad keys and
/// search text to browsers subscribed to /remote/events (typically the TV).
class FileServerRemoteScreen extends StatefulWidget {
  const FileServerRemoteScreen({super.key, required this.service, this.url});

  final FileServerService service;
  final String? url;

  @override
  State<FileServerRemoteScreen> createState() => _FileServerRemoteScreenState();
}

class _FileServerRemoteScreenState extends State<FileServerRemoteScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AdService _ads = sl<AdService>();
  Timer? _clientsTimer;
  Timer? _ticker;
  StreamSubscription<FileServerEvent>? _eventsSub;
  int _clients = 0;

  // Live playback state reported by the TV player.
  double _positionMs = 0;
  double _durationMs = 0;
  bool _paused = true;
  double _volume = 1.0;

  // Seek-drag state and rewarded unlock.
  bool _seeking = false;
  double _dragMs = 0;
  bool _unlocked = false;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    _unlocked = _ads.isSeekbarUnlocked();
    _pollClients();
    _clientsTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _pollClients());
    _eventsSub = widget.service.events.listen(_onEvent);
    // Advance the position locally between the ~1/s reports for a smooth bar.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_paused || _seeking || _durationMs <= 0) return;
      if (_positionMs >= _durationMs) return;
      setState(() => _positionMs =
          (_positionMs + 500).clamp(0, _durationMs).toDouble());
    });
  }

  @override
  void dispose() {
    _clientsTimer?.cancel();
    _ticker?.cancel();
    _eventsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onEvent(FileServerEvent event) {
    if (!mounted || event.type != FileServerEventType.playback) return;
    setState(() {
      _durationMs = event.durationMs.toDouble();
      _paused = event.paused;
      _volume = event.volume;
      if (!_seeking) _positionMs = event.positionMs.toDouble();
    });
  }

  Future<void> _pollClients() async {
    final clients = await widget.service.getRemoteClients();
    if (mounted && clients != _clients) setState(() => _clients = clients);
  }

  Future<void> _unlockSeekbar() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);
    final earned = await _ads.showRewardedForSeekbar();
    if (!mounted) return;
    setState(() {
      _unlocking = false;
      _unlocked = _ads.isSeekbarUnlocked();
    });
    if (!earned) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Watch the full ad to unlock the seekbar')));
    }
  }

  static String _fmtTime(double ms) {
    if (!ms.isFinite || ms < 0) ms = 0;
    final total = ms ~/ 1000;
    final s = total % 60;
    final m = (total ~/ 60) % 60;
    final h = total ~/ 3600;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  void _sendKey(String key) {
    widget.service.hapticTick();
    widget.service.sendRemoteKey(key);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TV Remote')),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) => orientation == Orientation.landscape
              ? _landscapeBody()
              : _portraitBody(),
        ),
      ),
      bottomNavigationBar: AdBanner(adUnitId: AdConfig.bannerRemote),
    );
  }

  Widget _portraitBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          _statusCard(),
          const SizedBox(height: 12),
          _searchField(),
          const SizedBox(height: 16),
          _playbackControls(),
          const SizedBox(height: 24),
          _dpad(),
          const SizedBox(height: 24),
          _mediaRow(),
        ],
      ),
    );
  }

  /// Landscape splits the screen: the D-pad on the left, playback/transport
  /// controls on the right, so nothing is buried below the fold.
  Widget _landscapeBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          _statusCard(),
          const SizedBox(height: 10),
          _searchField(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Pad on the left.
              Expanded(child: Center(child: _dpad())),
              const SizedBox(width: 20),
              // Controls on the right.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _playbackControls(),
                    const SizedBox(height: 20),
                    _mediaRow(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _playbackControls() {
    final cs = Theme.of(context).colorScheme;
    final dur = _durationMs;
    final hasMedia = dur > 0;
    final pos = (_seeking ? _dragMs : _positionMs).clamp(0, hasMedia ? dur : 1);
    final enabled = _unlocked && hasMedia;

    Widget controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Seek bar.
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: pos.toDouble(),
            max: hasMedia ? dur : 1,
            onChanged: enabled
                ? (v) => setState(() {
                      _seeking = true;
                      _dragMs = v;
                    })
                : null,
            onChangeEnd: enabled
                ? (v) {
                    widget.service.seekTo(v / 1000.0);
                    setState(() {
                      _positionMs = v;
                      _seeking = false;
                    });
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmtTime(pos.toDouble()),
                  style: monoTextStyle(fontSize: 12)
                      .copyWith(color: cs.onSurfaceVariant)),
              Text(hasMedia ? _fmtTime(dur) : '--:--',
                  style: monoTextStyle(fontSize: 12)
                      .copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Volume bar.
        Row(
          children: [
            Icon(_volume <= 0 ? Icons.volume_off : Icons.volume_up,
                size: 20, color: cs.onSurfaceVariant),
            Expanded(
              child: Slider(
                value: _volume.clamp(0.0, 1.0),
                onChanged: _unlocked
                    ? (v) {
                        setState(() => _volume = v);
                        widget.service.setVolume(v);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Stack(
        children: [
          controls,
          if (!_unlocked)
            Positioned.fill(
              child: _lockOverlay(),
            ),
        ],
      ),
    );
  }

  Widget _lockOverlay() {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: cs.surface.withValues(alpha: 0.86),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Watch a short ad to unlock the seekbar & volume for 12 hours.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _unlocking ? null : _unlockSeekbar,
              child: _unlocking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final cs = Theme.of(context).colorScheme;
    final connected = _clients > 0;
    final color = connected ? AppColors.running : AppColors.info;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(connected ? Icons.cast_connected : Icons.cast, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected
                      ? '$_clients device${_clients == 1 ? '' : 's'} listening'
                      : 'No devices connected',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                if (!connected && widget.url != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Open ${widget.url} in the TV browser first.',
                    style: monoTextStyle(fontSize: 12)
                        .copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: widget.service.sendRemoteText,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Type to search on the TV…',
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear, size: 18),
          onPressed: () {
            _searchController.clear();
            widget.service.sendRemoteText('');
          },
        ),
      ),
    );
  }

  Widget _dpad() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 264,
      height: 264,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: _DpadButton(
                icon: Icons.keyboard_arrow_up,
                onPress: () => _sendKey('up'),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _DpadButton(
                icon: Icons.keyboard_arrow_down,
                onPress: () => _sendKey('down'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _DpadButton(
                icon: Icons.keyboard_arrow_left,
                onPress: () => _sendKey('left'),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _DpadButton(
                icon: Icons.keyboard_arrow_right,
                onPress: () => _sendKey('right'),
              ),
            ),
            SizedBox(
              width: 88,
              height: 88,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.accent,
                ),
                onPressed: () => _sendKey('ok'),
                child: const Text(
                  'OK',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundButton(Icons.arrow_back, 'Back', () => _sendKey('back')),
        _roundButton(Icons.replay_10, '−10s', () => _sendKey('seekback')),
        _roundButton(_paused ? Icons.play_arrow : Icons.pause, 'Play/Pause',
            () => _sendKey('playpause'),
            emphasized: true),
        _roundButton(Icons.forward_10, '+10s', () => _sendKey('seekfwd')),
      ],
    );
  }

  Widget _roundButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool emphasized = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: emphasized ? 64 : 56,
          height: emphasized ? 64 : 56,
          child: emphasized
              ? FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: AppColors.accent,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: onPressed,
                  child: Icon(icon, size: 30),
                )
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  onPressed: onPressed,
                  child: Icon(icon, size: 24, color: cs.onSurface),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// D-pad arrow with press-and-hold repeat (fires once, then every 150ms after
/// a 400ms hold) — mirrors how a physical remote's arrows behave.
class _DpadButton extends StatefulWidget {
  const _DpadButton({required this.icon, required this.onPress});

  final IconData icon;
  final VoidCallback onPress;

  @override
  State<_DpadButton> createState() => _DpadButtonState();
}

class _DpadButtonState extends State<_DpadButton> {
  Timer? _holdTimer;

  void _start() {
    widget.onPress();
    _holdTimer = Timer(const Duration(milliseconds: 400), () {
      _holdTimer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => widget.onPress(),
      );
    });
  }

  void _stop() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          ),
          child: Icon(widget.icon, size: 34, color: cs.onSurface),
        ),
      ),
    );
  }
}

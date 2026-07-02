import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/file_server_service.dart';
import '../../core/theme/app_theme_data.dart';

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
  Timer? _clientsTimer;
  int _clients = 0;

  @override
  void initState() {
    super.initState();
    _pollClients();
    _clientsTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _pollClients());
  }

  @override
  void dispose() {
    _clientsTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pollClients() async {
    final clients = await widget.service.getRemoteClients();
    if (mounted && clients != _clients) setState(() => _clients = clients);
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            children: [
              _statusCard(),
              const SizedBox(height: 12),
              _searchField(),
              const Spacer(),
              _dpad(),
              const SizedBox(height: 24),
              _mediaRow(),
              const Spacer(),
            ],
          ),
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
        _roundButton(Icons.play_arrow, 'Play/Pause', () => _sendKey('playpause'),
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

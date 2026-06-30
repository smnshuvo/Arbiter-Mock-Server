import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/services/overlay_service.dart';
import '../../domain/entities/settings.dart';
import '../bloc/settings/settings_bloc.dart';

/// "Overlay" settings — choose what the floating bubble shows, with a live
/// preview that rebuilds as toggles change. Styled with the Arbiter Live
/// Activity design language (dark screen, mono labels, accent colours).
class OverlaySettingsScreen extends StatefulWidget {
  const OverlaySettingsScreen({super.key});

  @override
  State<OverlaySettingsScreen> createState() => _OverlaySettingsScreenState();
}

// Design tokens.
const _bg = Color(0xFF0F1217);
const _bubble = Color(0xFF0D1117);
const _text = Color(0xFFE9EEF4);
const _muted = Color(0xFF7A8595);
const _blue = Color(0xFF5FA0FF);
const _green = Color(0xFF3FD07A);
const _accent = Color(0xFF3B82F6);
const _mono = 'monospace';

class _OverlaySettingsScreenState extends State<OverlaySettingsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SettingsBloc>().add(LoadSettingsEvent());
  }

  void _set(Settings s, {bool? method, bool? endpoint, bool? status, bool? time}) {
    final m = method ?? s.overlayShowMethod;
    final e = endpoint ?? s.overlayShowEndpoint;
    final st = status ?? s.overlayShowStatus;
    final t = time ?? s.overlayShowTime;
    context.read<SettingsBloc>().add(
          SetOverlayContentEvent(method: m, endpoint: e, status: st, time: t),
        );
    // Update the live overlay window too, if it is currently showing.
    OverlayService().setOverlayContent(method: m, endpoint: e, status: st, time: t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        elevation: 0,
        title: const Text('Overlay', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          final s = state is SettingsLoaded ? state.settings : const Settings();
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _LivePreview(settings: s),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  'SHOW IN OVERLAY',
                  style: TextStyle(
                    color: _muted,
                    fontFamily: _mono,
                    fontSize: 11,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _ToggleRow(
                label: 'Request method',
                hint: 'GET, POST, PUT…',
                value: s.overlayShowMethod,
                onChanged: (v) => _set(s, method: v),
              ),
              _ToggleRow(
                label: 'Endpoint path',
                hint: '/v1/users',
                value: s.overlayShowEndpoint,
                onChanged: (v) => _set(s, endpoint: v),
              ),
              _ToggleRow(
                label: 'Response status',
                hint: '200, 401, 500…',
                value: s.overlayShowStatus,
                onChanged: (v) => _set(s, status: v),
              ),
              _ToggleRow(
                label: 'Response time',
                hint: '42 ms',
                value: s.overlayShowTime,
                onChanged: (v) => _set(s, time: v),
                last: true,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text(
                  'Tap any row — the preview pill rebuilds live.',
                  style: TextStyle(color: _muted, fontFamily: _mono, fontSize: 11, height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  final Settings settings;
  const _LivePreview({required this.settings});

  @override
  Widget build(BuildContext context) {
    final anyOn = settings.overlayShowMethod ||
        settings.overlayShowEndpoint ||
        settings.overlayShowStatus ||
        settings.overlayShowTime;

    final pill = <Widget>[
      Container(width: 7, height: 7, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
    ];
    if (settings.overlayShowMethod) {
      pill.add(const _Seg('GET', _blue, bold: true));
    }
    if (settings.overlayShowEndpoint) {
      pill.add(const _Seg('/v1/users', _text));
    }
    if (settings.overlayShowStatus) {
      pill.add(const _Seg('200', _green, bold: true));
    }
    if (settings.overlayShowTime) {
      pill.add(const _Seg('42ms', Color(0xFF9AA3B0)));
    }
    if (!anyOn) {
      pill.add(const _Seg('Arbiter', _muted));
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B2740), Color(0xFF2C2540)],
            ),
          ),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: _bubble,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 18, offset: Offset(0, 6))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < pill.length; i++) ...[
                    if (i > 0) const SizedBox(width: 9),
                    pill[i],
                  ],
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text(
            'Live preview · updates as you toggle',
            style: TextStyle(color: _muted, fontFamily: _mono, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _Seg extends StatelessWidget {
  final String text;
  final Color color;
  final bool bold;
  const _Seg(this.text, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontFamily: _mono,
        fontSize: 11,
        fontWeight: bold ? FontWeight.bold : FontWeight.w500,
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: value ? _text : const Color(0xFF9AA3B0),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(hint, style: const TextStyle(color: _muted, fontSize: 12, fontFamily: _mono)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: _accent,
            ),
          ],
        ),
      ),
    );
  }
}

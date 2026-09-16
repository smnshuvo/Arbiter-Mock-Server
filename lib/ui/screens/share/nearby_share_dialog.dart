import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../data/datasources/share/nearby_share_service.dart';
import '../../../data/datasources/share/share_code.dart';
import '../../../domain/entities/nearby_share.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/repositories/endpoint_repository.dart';
import '../../../domain/repositories/nearby_share_repository.dart';
import '../../bloc/dependency_container.dart';
import '../../bloc/profile/profile_bloc.dart';

/// Sender side of nearby sharing. The chosen collection is discoverable only
/// while this dialog is open; closing it stops sharing. A receiver needs the
/// PIN shown here to download.
class NearbyShareDialog extends StatefulWidget {
  final String? initialProfileId;

  const NearbyShareDialog({super.key, this.initialProfileId});

  @override
  State<NearbyShareDialog> createState() => _NearbyShareDialogState();
}

class _NearbyShareDialogState extends State<NearbyShareDialog> {
  final NearbyShareRepository _share = sl<NearbyShareRepository>();
  StreamSubscription<ShareEvent>? _events;

  String? _profileId;
  String? _pin;
  ShareSession? _session;
  bool _starting = false;
  String? _error;
  final List<String> _deliveredTo = [];

  @override
  void initState() {
    super.initState();
    _profileId = widget.initialProfileId;
    _events = _share.shareEvents.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case SharePinRotated(:final session):
            _session = session;
            _pin = session.pin;
            _error = 'Too many wrong attempts — a new code was generated.';
          case ShareDelivered(:final receiverAddress):
            _deliveredTo.add(receiverAddress);
        }
      });
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _share.stopSharing();
    super.dispose();
  }

  Future<void> _start(Profile profile) async {
    setState(() {
      _starting = true;
      _error = null;
      _deliveredTo.clear();
    });
    try {
      final endpoints = await sl<EndpointRepository>().getAllEndpoints(profileId: profile.id);
      final session =
          await _share.startSharing(collectionName: profile.name, endpoints: endpoints);
      if (mounted) {
        setState(() {
          _session = session;
          _pin = session.pin;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    await _share.stopSharing();
    if (mounted) {
      setState(() {
        _pin = null;
        _session = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final profileState = context.watch<ProfileBloc>().state;
    final profiles = profileState is ProfileLoaded ? profileState.profiles : const <Profile>[];
    final selected = profiles.where((p) => p.id == _profileId).firstOrNull ??
        (profiles.isNotEmpty ? profiles.first : null);
    final sharing = _pin != null;

    return AlertDialog(
      scrollable: true,
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: Text('Share nearby', style: t.sans(size: 16, weight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nearby Arbiter users on the same Wi-Fi can receive this collection '
              'while this window is open. Mock bodies and target URLs may contain '
              'secrets — only share on networks you trust.',
              style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selected?.id,
              decoration: const InputDecoration(
                labelText: 'Collection',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final p in profiles) DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: _starting
                  ? null
                  : (id) {
                      setState(() => _profileId = id);
                      final profile = profiles.where((p) => p.id == id).firstOrNull;
                      // Switching collection mid-share re-shares the new one.
                      if (sharing && profile != null) _start(profile);
                    },
            ),
            const SizedBox(height: 18),
            if (sharing) ...[
              if (_session?.code case final code?) ...[
                Center(child: ShareCodeQr(code: code, radius: t.radiusSm)),
                const SizedBox(height: 12),
                Text('CODE', textAlign: TextAlign.center, style: t.label),
                const SizedBox(height: 2),
                SelectableText(
                  ShareCode.format(code),
                  textAlign: TextAlign.center,
                  style: t.mono(size: 30, weight: FontWeight.w700, color: t.accent),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sharing as “${NearbyShareService.deviceName}”. On the other device open '
                  'Receive nearby, then scan this QR code or tap “Enter code”. '
                  'If it finds this device by itself, the PIN is $_pin.',
                  textAlign: TextAlign.center,
                  style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
                ),
              ] else ...[
                // No private IPv4 / fixed port to encode: PIN + address fallback.
                Text('PIN', textAlign: TextAlign.center, style: t.label),
                const SizedBox(height: 4),
                SelectableText(
                  _pin!.split('').join(' '),
                  textAlign: TextAlign.center,
                  style: t.mono(size: 34, weight: FontWeight.w700, color: t.accent),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sharing as “${NearbyShareService.deviceName}”. On the other device open '
                  'Receive nearby and enter this PIN.',
                  textAlign: TextAlign.center,
                  style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
                ),
                if (_session != null && _session!.addresses.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.surfaceMuted,
                      borderRadius: BorderRadius.circular(t.radiusSm),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Not showing up on the other device? Choose “Enter code” there and type:',
                          textAlign: TextAlign.center,
                          style:
                              t.sans(size: 11.5, weight: FontWeight.w500, color: t.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        for (final address in _session!.addresses)
                          SelectableText('$address:${_session!.port}',
                              textAlign: TextAlign.center,
                              style: t.mono(size: 14, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_deliveredTo.isEmpty) ...[
                    const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Waiting for a nearby device…',
                        style: t.sans(size: 12, color: t.textMuted)),
                  ] else ...[
                    Icon(Icons.check_circle, size: 16, color: t.green),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Sent to ${_deliveredTo.toSet().join(', ')}',
                          style: t.sans(size: 12, weight: FontWeight.w600, color: t.green)),
                    ),
                  ],
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: t.sans(size: 12, color: const Color(0xFFDC2626))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (sharing)
          OutlinedButton(onPressed: _stop, child: const Text('Stop sharing'))
        else
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: t.accent),
            onPressed: selected == null || _starting ? null : () => _start(selected),
            child: Text(_starting ? 'Starting…' : 'Start sharing'),
          ),
      ],
    );
  }
}

/// QR for a share code, on a white card. Fixed-size on purpose: [QrImageView]
/// lays out through a LayoutBuilder, which throws when an ancestor asks for
/// intrinsic dimensions — and a scrollable [AlertDialog] does exactly that
/// (the dialog rendered black on macOS and Android). A tight [SizedBox]
/// answers the intrinsic query without consulting the QR.
class ShareCodeQr extends StatelessWidget {
  final String code;
  final double size;
  final double radius;

  const ShareCodeQr({super.key, required this.code, this.size = 168, this.radius = 9});

  @override
  Widget build(BuildContext context) {
    const padding = 8.0;
    return SizedBox(
      width: size + padding * 2,
      height: size + padding * 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(padding),
          child: QrImageView(
            data: '${ShareCode.qrPrefix}$code',
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}

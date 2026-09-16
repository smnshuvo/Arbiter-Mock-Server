import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../data/datasources/share/nearby_share_protocol.dart';
import '../../../data/datasources/share/share_code.dart';
import '../../../domain/entities/nearby_share.dart';
import '../../../domain/repositories/nearby_share_repository.dart';
import '../../bloc/dependency_container.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';
import '../../bloc/profile/profile_bloc.dart';
import 'share_code_input_formatter.dart';
import 'share_code_scanner_screen.dart';

/// Receiver side of nearby sharing: searches the LAN while open, lets the user
/// pick a sharing device, enter its PIN, then name the new server before the
/// collection is saved.
class NearbyReceiveDialog extends StatefulWidget {
  const NearbyReceiveDialog({super.key});

  @override
  State<NearbyReceiveDialog> createState() => _NearbyReceiveDialogState();
}

class _NearbyReceiveDialogState extends State<NearbyReceiveDialog> {
  final NearbyShareRepository _share = sl<NearbyShareRepository>();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  /// Manually connected peer — kept apart from [_peers] so the next discovery
  /// refresh (which won't contain it) doesn't drop the selection.
  NearbyPeer? _manualPeer;
  bool _showAddressEntry = false;
  bool _connecting = false;
  StreamSubscription<List<NearbyPeer>>? _search;

  List<NearbyPeer> _peers = const [];
  NearbyPeer? _selected;
  bool _fetching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search = _share.discoverPeers().listen(
      (peers) {
        if (!mounted) return;
        setState(() {
          _peers = peers;
          // Keep the selection only while that sender is still around.
          if (_selected != null &&
              _selected != _manualPeer &&
              !peers.any((p) => p.sessionId == _selected!.sessionId)) {
            _selected = null;
          }
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e.toString());
      },
    );
  }

  @override
  void dispose() {
    _search?.cancel();
    _pinController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// The entry field takes the sharing device's short code (address + port +
  /// PIN, so it downloads straight away) or, as a fallback, a plain
  /// `address:port` (then the PIN is asked for like a discovered device).
  Future<void> _submitEntry() async {
    final input = _addressController.text;
    final code = ShareCode.decode(input);
    if (code != null) {
      await _receiveFromCode(code);
      return;
    }
    final parsed = NearbyShareProtocol.parseAddress(input);
    if (parsed == null) {
      setState(() => _error = input.contains('.')
          ? 'Enter the address as shown, e.g. 192.168.1.20:47778'
          : "That code isn't valid — check it against the sharing device.");
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final peer = await _share.connectTo(parsed.host, parsed.port);
      if (!mounted) return;
      setState(() {
        _manualPeer = peer;
        _selected = peer;
        _showAddressEntry = false;
        _pinController.clear();
      });
    } on NearbyShareException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _receiveFromCode(({String host, int port, String pin}) code) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final peer = await _share.connectTo(code.host, code.port);
      if (mounted) await _download(peer, code.pin);
    } on NearbyShareException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _scanCode() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ShareCodeScannerScreen()),
    );
    final code = scanned == null ? null : ShareCode.decode(scanned);
    if (code != null && mounted) await _receiveFromCode(code);
  }

  Future<void> _receive() async {
    final peer = _selected;
    if (peer != null) await _download(peer, _pinController.text);
  }

  Future<void> _download(NearbyPeer peer, String pin) async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final collection = await _share.fetchCollection(peer, pin);
      if (!mounted) return;
      final name = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NameServerDialog(collection: collection),
      );
      if (name == null || !mounted) return; // cancelled — nothing saved
      _save(collection, name);
    } on NearbyShareException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _save(SharedCollection collection, String name) {
    final profileId = const Uuid().v4();
    context.read<ProfileBloc>().add(CreateProfileEvent(name: name, id: profileId));
    // Fresh ids so receiving the same collection twice (or from this very
    // device) never collides with existing endpoint rows. Order is preserved.
    final endpoints = [
      for (final e in collection.endpoints)
        e.copyWith(id: const Uuid().v4(), profileId: profileId),
    ];
    context.read<EndpointBloc>().add(ImportEndpointsEvent(endpoints, profileId));
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Saved “$name” with ${endpoints.length} '
          'endpoint${endpoints.length == 1 ? '' : 's'}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return AlertDialog(
      scrollable: true,
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: Text('Receive nearby', style: t.sans(size: 16, weight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Searching this Wi-Fi for devices with “Share nearby” open…',
                    style: t.sans(size: 12, weight: FontWeight.w500, color: t.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: _peers.isEmpty && _manualPeer == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No one found yet. Guest or office Wi-Fi often blocks devices '
                        'from finding each other — enter or scan the code instead.',
                        textAlign: TextAlign.center,
                        style: t.sans(size: 12, color: t.textMuted),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        if (_manualPeer != null &&
                            !_peers.any((p) => p.sessionId == _manualPeer!.sessionId))
                          _peerTile(t, _manualPeer!),
                        for (final peer in _peers) _peerTile(t, peer),
                      ],
                    ),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _showAddressEntry = !_showAddressEntry),
                  icon: Icon(_showAddressEntry ? Icons.expand_less : Icons.keyboard, size: 16),
                  label: const Text('Enter code'),
                ),
                // Camera scanning is phone/tablet only.
                if (Platform.isAndroid || Platform.isIOS)
                  TextButton.icon(
                    onPressed: _connecting || _fetching ? null : _scanCode,
                    icon: const Icon(Icons.qr_code_scanner, size: 16),
                    label: const Text('Scan QR code'),
                  ),
              ],
            ),
            if (_showAddressEntry)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [ShareCodeInputFormatter()],
                      autocorrect: false,
                      style: t.mono(size: 15, weight: FontWeight.w700),
                      onSubmitted: (_) => _submitEntry(),
                      decoration: const InputDecoration(
                        labelText: 'Code shown on the sharing device',
                        hintText: 'K7Q-4MX-P2A',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _connecting || _fetching ? null : _submitEntry,
                    child: Text(_connecting || _fetching ? '…' : 'Connect'),
                  ),
                ],
              ),
            if (_selected != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                style: t.mono(size: 18, weight: FontWeight.w700),
                onSubmitted: (_) => _receive(),
                decoration: InputDecoration(
                  labelText: 'PIN shown on ${_selected!.deviceName}',
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: t.sans(size: 12, color: const Color(0xFFDC2626))),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: t.accent),
          onPressed: _selected == null || _fetching ? null : _receive,
          child: Text(_fetching ? 'Receiving…' : 'Receive'),
        ),
      ],
    );
  }

  Widget _peerTile(ArbTokens t, NearbyPeer peer) {
    final selected = peer.sessionId == _selected?.sessionId;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected ? t.accentSoft : null,
        border: Border.all(color: selected ? t.accent : t.border),
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.devices, color: selected ? t.accent : t.textSecondary),
        title: Text(peer.collectionName, style: t.sans(size: 13, weight: FontWeight.w700)),
        subtitle: Text(
          '${peer.deviceName} · ${peer.endpointCount} endpoint${peer.endpointCount == 1 ? '' : 's'}',
          style: t.sans(size: 11.5, color: t.textSecondary),
        ),
        onTap: () => setState(() {
          _selected = peer;
          _error = null;
          _pinController.clear();
        }),
      ),
    );
  }
}

/// Asked after a successful download and before anything is written.
class _NameServerDialog extends StatefulWidget {
  final SharedCollection collection;

  const _NameServerDialog({required this.collection});

  @override
  State<_NameServerDialog> createState() => _NameServerDialogState();
}

class _NameServerDialogState extends State<_NameServerDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.collection.collectionName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.collection.endpoints.length;
    return AlertDialog(
      title: const Text('Name this server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Received $count endpoint${count == 1 ? '' : 's'} from '
              '${widget.collection.deviceName}. It will be saved as a new server.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Server name',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Discard')),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

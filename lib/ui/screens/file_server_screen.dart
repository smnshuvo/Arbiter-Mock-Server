import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ads/ad_config.dart';
import '../../core/ads/ad_service.dart';
import '../../core/services/file_server_service.dart';
import '../../core/theme/app_theme_data.dart';
import '../bloc/dependency_container.dart';
import 'file_server_remote_screen.dart';

/// Android-only Wi-Fi file server control screen.
///
/// Owns its own state (not a mock-server [Profile]): the shared folder, chosen port,
/// running URL, live request counter, and library-scan progress. Talks to the native
/// server through [FileServerService].
class FileServerScreen extends StatefulWidget {
  const FileServerScreen({super.key});

  @override
  State<FileServerScreen> createState() => _FileServerScreenState();
}

class _FileServerScreenState extends State<FileServerScreen> {
  static const _portPrefKey = 'file_server_port';
  static const _uploadsPrefKey = 'file_server_uploads';
  static const _authEnabledPrefKey = 'file_server_auth_enabled';
  static const _authUserPrefKey = 'file_server_auth_user';
  static const _authPassPrefKey = 'file_server_auth_pass';
  static const _idleStopPrefKey = 'file_server_stop_if_idle';

  final FileServerService _service = FileServerService();
  final TextEditingController _portController =
      TextEditingController(text: '8080');
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  StreamSubscription<FileServerEvent>? _eventsSub;
  Timer? _statsTimer;

  SharedFolder? _folder;
  bool _running = false;
  bool _busy = false;
  String? _url;
  int _requestCount = 0;
  int _remoteClients = 0;
  bool _uploadsEnabled = false;
  bool _authEnabled = false;
  bool _stopIfIdle = true;

  int _totalBytes = 0;
  int _speedBps = 0;

  bool _scanning = false;
  int _scanDone = 0;
  int _scanTotal = 0;

  @override
  void initState() {
    super.initState();
    _restore();
    _eventsSub = _service.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _statsTimer?.cancel();
    _portController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPort = prefs.getInt(_portPrefKey);
    final uploads = prefs.getBool(_uploadsPrefKey) ?? false;
    final stopIfIdle = prefs.getBool(_idleStopPrefKey) ?? true;
    final authEnabled = prefs.getBool(_authEnabledPrefKey) ?? false;
    final authUser = prefs.getString(_authUserPrefKey) ?? '';
    final authPass = prefs.getString(_authPassPrefKey) ?? '';
    final folder = await _service.getSavedFolder();
    final scanning = await _service.isScanning();
    // The foreground service keeps the server alive after this screen is
    // disposed, so ask the native side whether it is still running instead of
    // defaulting to "stopped" (which left the port busy behind a stale UI).
    final status = await _service.getStatus();
    final ip = status.running ? await _service.getLocalIp() : null;
    final totalBytes = status.running ? await _service.getTotalBytes() : 0;
    if (!mounted) return;
    setState(() {
      if (savedPort != null) _portController.text = savedPort.toString();
      _uploadsEnabled = uploads;
      _stopIfIdle = stopIfIdle;
      _authEnabled = authEnabled;
      _userController.text = authUser;
      _passController.text = authPass;
      _folder = folder;
      _scanning = scanning;
      if (status.running) {
        _running = true;
        _portController.text = status.port.toString();
        _url = ip != null ? 'http://$ip:${status.port}' : null;
        _requestCount = status.requestCount;
        // Baseline for the speed display; the first poll delta starts from here.
        _totalBytes = totalBytes;
      }
    });
    if (status.running) _startStatsPolling();
  }

  /// Credentials to send natively: null user means anonymous access.
  String? get _effectiveAuthUser {
    if (!_authEnabled) return null;
    final user = _userController.text.trim();
    return user.isEmpty ? null : user;
  }

  Future<void> _setAuthEnabled(bool enabled) async {
    setState(() => _authEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_authEnabledPrefKey, enabled);
    if (_running) await _applyAuthLive();
  }

  Future<void> _persistAuthFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authUserPrefKey, _userController.text.trim());
    await prefs.setString(_authPassPrefKey, _passController.text);
    if (_running) await _applyAuthLive();
  }

  Future<void> _applyAuthLive() =>
      _service.setAuth(_effectiveAuthUser, _passController.text);

  Future<void> _setUploadsEnabled(bool enabled) async {
    setState(() => _uploadsEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_uploadsPrefKey, enabled);
    // Takes effect immediately on an already-running server.
    if (_running) await _service.setUploadsEnabled(enabled);
  }

  Future<void> _setStopIfIdle(bool enabled) async {
    setState(() => _stopIfIdle = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_idleStopPrefKey, enabled);
    // Applies on the next server start (the watchdog is configured at startup).
    if (_running) {
      _snack('Takes effect the next time you start the server');
    }
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollStats());
  }

  void _stopStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  Future<void> _pollStats() async {
    final total = await _service.getTotalBytes();
    if (!mounted) return;
    setState(() {
      // 1s poll interval, so the delta is bytes/second.
      _speedBps = (total - _totalBytes).clamp(0, 1 << 62);
      _totalBytes = total;
    });
  }

  static String _fmtBytes(num bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(1)} ${units[i]}';
  }

  void _onEvent(FileServerEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case FileServerEventType.requests:
          _requestCount = event.requestCount;
          break;
        case FileServerEventType.remote:
          _remoteClients = event.remoteClients;
          break;
        case FileServerEventType.scan:
          _scanning = !event.complete;
          _scanDone = event.done;
          _scanTotal = event.total;
          break;
        case FileServerEventType.stopped:
          _running = false;
          _url = null;
          _remoteClients = 0;
          _stopStatsPolling();
          break;
        case FileServerEventType.playback:
          break; // Only the remote screen consumes playback events.
      }
    });
    if (event.type == FileServerEventType.scan && event.complete) {
      _snack('Scan complete · ${event.total} media file(s)');
    } else if (event.type == FileServerEventType.stopped) {
      _snack('Server stopped after 1 hour of inactivity');
    }
  }

  int get _port => int.tryParse(_portController.text.trim()) ?? 8080;

  Future<void> _pickFolder() async {
    final folder = await _service.pickFolder();
    if (folder != null && mounted) {
      setState(() => _folder = folder);
      // First-time scan kicks off automatically per the plan.
      await _service.scanLibrary(rootUri: folder.uri);
    }
  }

  Future<void> _toggleServer() async {
    if (_busy) return;
    if (_running) {
      setState(() => _busy = true);
      await _service.stopServer();
      _stopStatsPolling();
      if (!mounted) return;
      setState(() {
        _running = false;
        _url = null;
        _remoteClients = 0;
        _busy = false;
      });
      return;
    }

    final folder = _folder;
    if (folder == null) {
      _snack('Pick a folder to share first');
      return;
    }
    if (_authEnabled &&
        (_userController.text.trim().isEmpty || _passController.text.isEmpty)) {
      _snack('Enter a username and password, or turn off "Require login"');
      return;
    }
    setState(() => _busy = true);
    await _persistPort();
    await _persistAuthFields();
    final ok = await _service.startServer(
      port: _port,
      rootUri: folder.uri,
      uploadsEnabled: _uploadsEnabled,
      authUser: _effectiveAuthUser,
      authPass: _passController.text,
      stopIfIdle: _stopIfIdle,
    );
    final ip = ok ? await _service.getLocalIp() : null;
    if (!mounted) return;
    setState(() {
      _running = ok;
      _url = (ok && ip != null) ? 'http://$ip:$_port' : null;
      _requestCount = 0;
      _totalBytes = 0;
      _speedBps = 0;
      _busy = false;
    });
    if (ok) _startStatsPolling();
    if (!ok) _snack('Failed to start the server');
    if (ok && ip == null) _snack('Server started, but no Wi-Fi address found');
  }

  Future<void> _persistPort() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_portPrefKey, _port);
  }

  Future<void> _scan() async {
    final folder = _folder;
    if (folder == null) {
      _snack('Pick a folder first');
      return;
    }
    await _service.scanLibrary(rootUri: folder.uri);
    if (mounted) setState(() => _scanning = true);
  }

  void _copyUrl() {
    final url = _url;
    if (url == null) return;
    Clipboard.setData(ClipboardData(text: url));
    _snack('Copied $url');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('File Server')),
      body: FileServerService.isSupported
          ? _buildBody()
          : const _UnsupportedNotice(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _wifiNote(),
          const SizedBox(height: 16),
          _folderCard(),
          const SizedBox(height: 16),
          _portField(),
          const SizedBox(height: 16),
          _uploadsToggle(),
          const SizedBox(height: 16),
          _idleStopToggle(),
          const SizedBox(height: 16),
          _accessCard(),
          const SizedBox(height: 16),
          _startStopButton(),
          if (_running && _url != null) ...[
            const SizedBox(height: 20),
            _urlAndQr(_url!),
            const SizedBox(height: 16),
            _remoteCard(),
            const SizedBox(height: 16),
            _requestCounter(),
            const SizedBox(height: 16),
            _trafficCard(),
          ],
          const SizedBox(height: 24),
          _scanSection(),
        ],
      ),
    );
  }

  Widget _wifiNote() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi, color: AppColors.info, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Devices must be on the same Wi-Fi network. The server is '
              'unreachable over mobile data.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderCard() {
    final folder = _folder;
    return _card(
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 28, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder?.name ?? 'No folder selected',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  folder == null ? 'Pick a folder to share' : 'Shared folder',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            // Changing the folder while running would serve a stale root.
            onPressed: _running ? null : _pickFolder,
            child: Text(folder == null ? 'Pick' : 'Change'),
          ),
        ],
      ),
    );
  }

  Widget _portField() {
    return _card(
      child: Row(
        children: [
          const Icon(Icons.lan_outlined, size: 24, color: AppColors.accent),
          const SizedBox(width: 12),
          const Text('Port', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _portController,
              enabled: !_running,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _startStopButton() {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: _busy ? null : _toggleServer,
        style: FilledButton.styleFrom(
          backgroundColor: _running ? AppColors.error : AppColors.running,
        ),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(_running ? Icons.stop : Icons.play_arrow),
        label: Text(
          _running ? 'Stop Server' : 'Start Server',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _urlAndQr(String url) {
    return _card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: url,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  url,
                  style: monoTextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copy URL',
                onPressed: _copyUrl,
              ),
            ],
          ),
          Text(
            'Scan the QR or open this URL in any browser on the same network.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadsToggle() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Row(
        children: [
          const Icon(Icons.upload_file_outlined, size: 24, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Allow uploads',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Browsers on the network can add files to the shared folder.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(value: _uploadsEnabled, onChanged: _setUploadsEnabled),
        ],
      ),
    );
  }

  Widget _idleStopToggle() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Row(
        children: [
          const Icon(Icons.timer_off_outlined, size: 24, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stop server if idle',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Automatically stop after 1 hour with no requests to save battery.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Switch(value: _stopIfIdle, onChanged: _setStopIfIdle),
        ],
      ),
    );
  }

  Widget _accessCard() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 24, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Require login',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _authEnabled
                          ? 'Browsers must sign in with the credentials below.'
                          : 'Anonymous — anyone on the network can access.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(value: _authEnabled, onChanged: _setAuthEnabled),
            ],
          ),
          if (_authEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _userController,
              onChanged: (_) => _persistAuthFields(),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passController,
              onChanged: (_) => _persistAuthFields(),
              obscureText: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Password',
                prefixIcon: Icon(Icons.key_outlined, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trafficCard() {
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.speed, size: 22, color: AppColors.accent),
              const SizedBox(width: 12),
              const Text('Current speed',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '${_fmtBytes(_speedBps)}/s',
                style: monoTextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.data_usage, size: 22, color: AppColors.accent),
              const SizedBox(width: 12),
              const Text('Total transferred',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                _fmtBytes(_totalBytes),
                style: monoTextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _remoteCard() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Row(
        children: [
          const Icon(Icons.settings_remote_outlined,
              size: 24, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TV Remote',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  _remoteClients > 0
                      ? '$_remoteClients device${_remoteClients == 1 ? '' : 's'} listening'
                      : 'Control the web UI open on your TV.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () {
              // Full-screen ad on opening the remote, throttled to once per hour.
              sl<AdService>().maybeShowInterstitial(
                'ad_gate_open_remote',
                AdConfig.interstitialOpenRemote,
              );
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      FileServerRemoteScreen(service: _service, url: _url),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Widget _requestCounter() {
    return _card(
      child: Row(
        children: [
          const Icon(Icons.swap_vert, size: 22, color: AppColors.running),
          const SizedBox(width: 12),
          const Text('Requests served', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            '$_requestCount',
            style: monoTextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _scanSection() {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.video_library_outlined,
                  size: 22, color: AppColors.accent),
              const SizedBox(width: 12),
              const Text('Media library', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_scanning)
                TextButton(
                  onPressed: () => _service.cancelScan(),
                  child: const Text('Cancel'),
                )
              else
                TextButton(
                  onPressed: _folder == null ? null : _scan,
                  child: const Text('Scan'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_scanning) ...[
            LinearProgressIndicator(
              value: _scanTotal > 0 ? _scanDone / _scanTotal : null,
            ),
            const SizedBox(height: 6),
            Text(
              'Scanning — $_scanDone of $_scanTotal files',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ] else
            Text(
              'Scan builds thumbnails and metadata for the browser library grid.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phonelink_off,
                size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'The Wi-Fi file server is Android-only for now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

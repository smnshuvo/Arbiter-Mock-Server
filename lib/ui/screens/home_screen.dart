import 'package:arbiter_mock_server/core/ads/ad_config.dart';
import 'package:arbiter_mock_server/core/ads/ad_service.dart';
import 'package:arbiter_mock_server/core/theme/theme_cubit.dart';
import 'package:arbiter_mock_server/core/services/file_server_service.dart';
import 'package:arbiter_mock_server/core/services/foreground_service.dart';
import 'package:arbiter_mock_server/core/services/overlay_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme_data.dart';
import '../../domain/entities/interception_mode.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../bloc/dependency_container.dart';
import '../bloc/interception/interception_bloc.dart';
import '../bloc/interception/interception_event.dart';
import '../bloc/interception/interception_state.dart';
import '../bloc/profile/profile_bloc.dart';
import '../bloc/server/server_bloc.dart';
import '../dialog/interception_dialog.dart';
import '../widgets/glowing_icon_widget.dart';
import '../widgets/grey_out_icon_widget.dart';
import 'endpoint_screen.dart';
import 'file_server_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _portController =
      TextEditingController(text: '8080');

  static const iconAssetPath = 'assets/app_icon/app_icon.png';

  /// Per-profile endpoint counts, shown as a chip on each server card. Loaded
  /// lazily (best-effort) whenever the profile list changes or we return from
  /// the endpoints screen.
  Map<String, int> _endpointCounts = {};
  bool _loadingCounts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    print('HomeScreen: ============================================');
    print('HomeScreen: initState called');
    print('HomeScreen: Initializing ForegroundService');
    // Initialize foreground service and set callback for stop server from notification
    ForegroundService.initialize();

    print('HomeScreen: Setting onStopServerRequested callback');
    ForegroundService.onStopServerRequested = () async {
      print('HomeScreen: ============================================');
      print('HomeScreen: onStopServerRequested callback TRIGGERED!');
      print('HomeScreen: This means the MethodChannel call reached Flutter successfully');

      try {
        // Stop the server via ServerBloc
        print('HomeScreen: Dispatching StopServerEvent to ServerBloc');
        context.read<ServerBloc>().add(StopServerEvent());
        print('HomeScreen: StopServerEvent dispatched successfully');
        print('HomeScreen: ============================================');
        return true;
      } catch (e, stackTrace) {
        print('HomeScreen: ERROR dispatching StopServerEvent: $e');
        print('HomeScreen: StackTrace: $stackTrace');
        print('HomeScreen: ============================================');
        return false;
      }
    };

    // Floating overlay live activity (Android) — actions drive the existing blocs.
    OverlayService.initialize();
    OverlayService.onStopServerRequested = () async {
      if (!mounted) return false;
      final serverState = context.read<ServerBloc>().state;
      context.read<ServerBloc>().add(
            serverState is MultiServerRunning
                ? StopAllProfilesEvent()
                : StopServerEvent(),
          );
      return true;
    };
    OverlayService.onInterceptionContinue = (id) {
      if (mounted) {
        context.read<InterceptionBloc>().add(ContinueWithoutModificationEvent(id));
      }
    };
    OverlayService.onInterceptionDrop = (id) {
      if (mounted) {
        context.read<InterceptionBloc>().add(CancelInterceptionEvent(id));
      }
    };
    OverlayService.onOpenLogs = () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LogsScreen()),
        );
      }
    };
    OverlayService.onToggleInterception = (enabled) {
      if (mounted) {
        context.read<InterceptionBloc>().add(
              SetInterceptionModeEvent(
                enabled ? InterceptionMode.both : InterceptionMode.none,
              ),
            );
      }
    };

    print('HomeScreen: Callback set successfully');
    print('HomeScreen: Checking server status');
    context.read<ServerBloc>().add(CheckServerStatusEvent());
    print('HomeScreen: Starting interception watcher');
    context.read<InterceptionBloc>().add(StartWatchingInterceptions());
    print('HomeScreen: ============================================');

    // Profiles are loaded app-wide at startup; if they are already available,
    // seed the endpoint counts here (the BlocListener only fires on changes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profileState = context.read<ProfileBloc>().state;
      if (profileState is ProfileLoaded) {
        _loadEndpointCounts(profileState.profiles);
      }
    });
  }

  final OverlayService _overlay = OverlayService();
  bool _isForeground = true;
  bool _interceptionDialogOpen = false;

  /// Shows or hides the floating overlay. The overlay floats over OTHER apps, so
  /// it is shown only when Arbiter is backgrounded (and the Settings toggle is
  /// on, the permission is granted, and a server is running). When Arbiter is in
  /// front it is hidden so it never covers the in-app UI (e.g. the edit dialog).
  Future<void> _syncOverlay(ServerState state) async {
    final interceptionState = context.read<InterceptionBloc>().state;
    final interceptionOn =
        interceptionState is InterceptionEnabled || interceptionState is InterceptionPending;

    final ({String address, int port})? running = switch (state) {
      ServerRunning s => (address: Uri.tryParse(s.url)?.host ?? 'localhost', port: s.port),
      MultiServerRunning s when s.runningServers.isNotEmpty =>
        (address: Uri.tryParse(s.runningServers.first.url)?.host ?? 'localhost', port: s.runningServers.first.port),
      _ => null,
    };

    if (running == null) {
      await _overlay.hide();
      return;
    }

    final settings = await sl<SettingsRepository>().getSettings();
    if (!settings.showFloatingOverlay || _isForeground || !await _overlay.hasPermission()) {
      await _overlay.hide();
      return;
    }

    await _overlay.show();
    await _overlay.setServerStatus(address: running.address, port: running.port);
    await _overlay.setOverlayContent(
      method: settings.overlayShowMethod,
      endpoint: settings.overlayShowEndpoint,
      status: settings.overlayShowStatus,
      time: settings.overlayShowTime,
    );
    await _overlay.setInterceptionEnabled(interceptionOn);
  }

  /// Flips the overlay to/from the intercepted call-to-action.
  void _syncOverlayInterception(InterceptionState state) {
    if (state is InterceptionPending) {
      final i = state.interception;
      _overlay.setIntercepted(
        id: i.id,
        type: i.isResponse ? 'response' : 'request',
        method: i.method,
        url: i.url,
        statusCode: i.isResponse ? i.statusCode : null,
        body: i.isResponse ? i.responseBody : i.body,
      );
    } else {
      _overlay.clearIntercepted();
    }
    // Reflect the on/off state in the overlay's interception switch.
    if (state is InterceptionEnabled || state is InterceptionPending) {
      _overlay.setInterceptionEnabled(true);
    } else if (state is InterceptionDisabled) {
      _overlay.setInterceptionEnabled(false);
    }
  }

  void _showInterceptionDialog(InterceptionPending state) {
    _interceptionDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider.value(
        value: context.read<InterceptionBloc>(),
        child: InterceptionDialog(
          interception: state.interception,
          timeoutSeconds: state.timeoutSeconds,
        ),
      ),
    ).then((_) => _interceptionDialogOpen = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _portController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      // Arbiter is back in front: hide the overlay so it doesn't cover the UI.
      _syncOverlay(context.read<ServerBloc>().state);
      // Surface the dialog for a still-held intercept (e.g. after tapping Edit).
      final interceptionState = context.read<InterceptionBloc>().state;
      if (interceptionState is InterceptionPending && !_interceptionDialogOpen) {
        _showInterceptionDialog(interceptionState);
      }
    } else if (state == AppLifecycleState.paused) {
      _isForeground = false;
      // Arbiter went to the background: float the overlay over the foreground app.
      _syncOverlay(context.read<ServerBloc>().state);
    }
  }

  Future<bool> _checkAndRequestNotificationPermission() async {
    // Check if notification permission is granted
    final status = await Permission.notification.status;

    if (status.isGranted) {
      return true;
    }

    // If not granted, show dialog explaining why we need it
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Notification Permission Required'),
        content: const Text(
          'To show the server status and endpoint hits in the notification, we need your permission to display notifications.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (result != true) {
      return false;
    }

    // Request permission
    final requestResult = await Permission.notification.request();

    if (requestResult.isGranted) {
      return true;
    }

    // Show error dialog if permission denied
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permission Denied'),
          content: const Text(
            'Notification permission is required to run the server in the background. Please enable it in app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    return false;
  }

  /// Best-effort load of per-profile endpoint counts for the card chips.
  Future<void> _loadEndpointCounts(List<Profile> profiles) async {
    if (_loadingCounts) return;
    _loadingCounts = true;
    try {
      final repo = sl<EndpointRepository>();
      final counts = <String, int>{};
      for (final profile in profiles) {
        final endpoints = await repo.getAllEndpoints(profileId: profile.id);
        counts[profile.id] = endpoints.length;
      }
      if (mounted) setState(() => _endpointCounts = counts);
    } catch (_) {
      // Counts are decorative; ignore failures.
    } finally {
      _loadingCounts = false;
    }
  }

  /// Maps each running profile id to its live url/port for the current state.
  Map<String, ({String url, int port})> _runningMap(ServerState state) {
    if (state is MultiServerRunning) {
      return {
        for (final srv in state.runningServers)
          srv.profileId: (url: srv.url, port: srv.port),
      };
    }
    if (state is ServerRunning) {
      return {state.profileId: (url: state.url, port: state.port)};
    }
    return const {};
  }

  int _nextFreePort(int preferred, Set<int> used) {
    if (!used.contains(preferred)) return preferred;
    var port = 8080;
    while (used.contains(port)) {
      port++;
    }
    return port;
  }

  /// Opens a profile's endpoints. Switches the active profile first so the
  /// endpoints screen (which follows the active profile) shows the right set.
  Future<void> _openProfile(Profile profile) async {
    context.read<ProfileBloc>().add(SwitchActiveProfileEvent(profile.id));
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EndpointsScreen()),
    );
    if (!mounted) return;
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      _loadEndpointCounts(profileState.profiles);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<ServerBloc, ServerState>(
          listener: (context, state) {
            if (state is ServerError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.error,
                ),
              );
              // Restore the actual running state — ServerError wipes the previous state
              context.read<ServerBloc>().add(CheckServerStatusEvent());
            }

            // Stop foreground service when server stops
            if (state is ServerStopped) {
              print('HomeScreen: Server stopped, stopping foreground service');
              ForegroundService().stopForegroundService();
            }

            _syncOverlay(state);
          },
          builder: (context, state) {
            return MultiBlocListener(
              listeners: [
                BlocListener<InterceptionBloc, InterceptionState>(
                  listener: (context, interceptionState) {
                    _syncOverlayInterception(interceptionState);
                    // Only show the in-app dialog while Arbiter is in front; when it is
                    // backgrounded the floating overlay handles intercepts. This avoids
                    // a stale dialog appearing on return for an already-resolved hold.
                    if (interceptionState is InterceptionPending &&
                        _isForeground &&
                        !_interceptionDialogOpen) {
                      _showInterceptionDialog(interceptionState);
                    }
                  },
                ),
                BlocListener<ProfileBloc, ProfileState>(
                  listener: (context, profileState) {
                    if (profileState is ProfileLoaded) {
                      _loadEndpointCounts(profileState.profiles);
                    }
                  },
                ),
              ],
              child: _buildContent(state),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(ServerState state) {
    final interceptionState = context.watch<InterceptionBloc>().state;
    final interceptionOn = interceptionState is InterceptionEnabled ||
        interceptionState is InterceptionPending;

    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        final profiles =
            profileState is ProfileLoaded ? profileState.profiles : const <Profile>[];
        final running = _runningMap(state);
        final runningCount =
            profiles.where((p) => running.containsKey(p.id)).length;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(state),
              const SizedBox(height: 20),
              _buildTitle(profiles.length, runningCount),
              const SizedBox(height: 16),
              _buildStatsStrip(),
              const SizedBox(height: 16),
              if (profileState is! ProfileLoaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                ...profiles.map((profile) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildServerCard(
                        profile,
                        running[profile.id],
                        state,
                        interceptionOn,
                      ),
                    )),
                _buildNewServerButton(state),
                if (FileServerService.isSupported) ...[
                  const SizedBox(height: 12),
                  _buildFileServerEntry(),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  /// Android-only entry to the Wi-Fi file server — a distinct server type that is
  /// deliberately not modelled as a mock [Profile].
  Widget _buildFileServerEntry() {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FileServerScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.surface,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_tethering, color: AppColors.info, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wi-Fi File Server',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Share a folder over your local network',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ServerState state) {
    final cs = Theme.of(context).colorScheme;
    final anyRunning = state is ServerRunning || state is MultiServerRunning;

    return Row(
      children: [
        SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: anyRunning
                ? const GlowingIconWidget(
                    iconAssetPath: iconAssetPath,
                    size: 44,
                    glowColor: AppColors.runningGlow,
                  )
                : const GreyOutIconWidget(
                    iconAssetPath: iconAssetPath,
                    size: 44,
                    opacity: 0.6,
                    greyIntensity: 1.0,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Arbiter',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'mock servers',
                style: monoTextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            final isDark = themeMode == ThemeMode.dark;
            return IconButton(
              icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              tooltip: 'Toggle theme',
              onPressed: () => context.read<ThemeCubit>().toggleTheme(),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.receipt_long_outlined),
          tooltip: 'Logs',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LogsScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
            // The overlay toggle may have changed; re-evaluate against server state.
            if (mounted) _syncOverlay(context.read<ServerBloc>().state);
          },
        ),
      ],
    );
  }

  Widget _buildTitle(int total, int running) {
    final summary = total == 0
        ? 'No servers yet'
        : running == 0
            ? '$total server${total == 1 ? '' : 's'} · none running'
            : '$running of $total running';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Servers',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          summary,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // NOTE: Network + Disk figures are static placeholders — there is no metrics
  // data source yet (tracked in task.md §5.2). Styled to match the design so the
  // real numbers can be wired in later without a layout change.
  Widget _buildStatsStrip() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.swap_vert,
            iconColor: AppColors.info,
            label: 'NETWORK',
            value: '0.0',
            unit: 'MB/s',
            footer: Row(
              children: [
                Text('▲ 0',
                    style: monoTextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.running)),
                const SizedBox(width: 10),
                Text('▼ 0',
                    style: monoTextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.info)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            icon: Icons.storage_outlined,
            iconColor: AppColors.interception,
            label: 'DISK',
            value: '0',
            unit: '/ 0 GB',
            footer: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: 0,
                minHeight: 5,
                backgroundColor: Theme.of(context).dividerColor,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    required Widget footer,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 13, color: iconColor),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: monoTextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: monoTextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(width: 5),
              Text(unit,
                  style: monoTextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 9),
          footer,
        ],
      ),
    );
  }

  Widget _buildServerCard(
    Profile profile,
    ({String url, int port})? info,
    ServerState state,
    bool interceptionOn,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isRunning = info != null;
    final isFtp = profile.type == ServerType.ftp;
    final scheme = isFtp ? 'ftp' : 'http';
    final urlText = isRunning ? info.url : '$scheme://localhost:${profile.port}';
    final epCount = _endpointCounts[profile.id];

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openProfile(profile),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _statusDot(isRunning),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _typeChip(isFtp),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Text(
                    urlText,
                    style: monoTextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _statusChip(isRunning),
                      if (epCount != null)
                        _infoChip('$epCount endpoint${epCount == 1 ? '' : 's'}'),
                      if (isRunning && interceptionOn) _interceptionChip(),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _runButton(
              isRunning,
              () => isRunning
                  ? context.read<ServerBloc>().add(StopProfileEvent(profile.id))
                  : _showStartProfileSheet(
                      defaultPort: _nextFreePort(
                        profile.port,
                        _runningMap(state).values.map((e) => e.port).toSet(),
                      ),
                      defaultUseDeviceIp: profile.settings.useDeviceIp,
                      initialProfileId: profile.id,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(bool running) {
    final color =
        running ? AppColors.running : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _typeChip(bool isFtp) {
    final color = isFtp ? AppColors.interception : AppColors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isFtp ? 'FTP' : 'HTTP',
        style: monoTextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _runButton(bool running, VoidCallback onTap) {
    final color = running ? AppColors.error : AppColors.running;
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
      label: Text(
        running ? 'Stop' : 'Run',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        elevation: 2,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _statusChip(bool running) {
    final color =
        running ? AppColors.running : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        running ? 'running' : 'stopped',
        style: monoTextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _infoChip(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: monoTextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _interceptionChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.interception.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        'intercepting',
        style: monoTextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.interception),
      ),
    );
  }

  Widget _buildNewServerButton(ServerState state) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        final usedPorts = _runningMap(state).values.map((e) => e.port).toSet();
        _showStartProfileSheet(defaultPort: _nextFreePort(8080, usedPorts));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text(
              'New server',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStartProfileSheet({
    int defaultPort = 8080,
    bool defaultUseDeviceIp = false,
    String? initialProfileId,
  }) async {
    var profileState = context.read<ProfileBloc>().state;
    if (profileState is! ProfileLoaded) {
      // Right after launch the profiles are still being read from the DB. Without
      // waiting, this first tap on "Start Server" would be silently dropped and
      // the user would have to tap again. Kick off / wait for the load instead.
      final profileBloc = context.read<ProfileBloc>();
      if (profileState is ProfileInitial) profileBloc.add(LoadProfilesEvent());
      profileState = await profileBloc.stream
          .firstWhere((s) => s is ProfileLoaded || s is ProfileError)
          .timeout(const Duration(seconds: 3), onTimeout: () => profileBloc.state);
      if (!mounted) return;
    }
    final loaded = profileState;
    if (loaded is! ProfileLoaded) return;

    final serverState = context.read<ServerBloc>().state;
    final runningProfileIds = serverState is MultiServerRunning
        ? serverState.runningServers.map((s) => s.profileId).toSet()
        : serverState is ServerRunning
            ? <String>{serverState.profileId}
            : const <String>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _StartProfileSheet(
        profiles: loaded.profiles,
        runningProfileIds: runningProfileIds,
        defaultPort: defaultPort,
        defaultUseDeviceIp: defaultUseDeviceIp,
        initialProfileId: initialProfileId,
        onStart: (profileId, profileName, port, useDeviceIp, passThroughUrl, autoPassThrough) async {
          final hasPermission = await _checkAndRequestNotificationPermission();
          if (!hasPermission || !mounted) return;
          Navigator.pop(ctx);
          // Save pass-through settings back to the profile so the URL persists
          final profile = loaded.profiles.firstWhere((p) => p.id == profileId);
          final updatedProfile = profile.copyWith(
            settings: profile.settings.copyWith(
              globalPassThroughUrl: passThroughUrl,
              clearPassThroughUrl: passThroughUrl == null,
              autoPassThrough: autoPassThrough,
            ),
            updatedAt: DateTime.now(),
          );
          context.read<ProfileBloc>().add(UpdateProfileEvent(updatedProfile));
          context.read<ServerBloc>().add(StartProfileEvent(
            profileId: profileId,
            profileName: profileName,
            port: port,
            useDeviceIp: useDeviceIp,
            passThroughUrl: passThroughUrl,
            autoPassThrough: autoPassThrough,
          ));
          // Full-screen ad on server start, throttled to once per hour.
          sl<AdService>().maybeShowInterstitial(
            'ad_gate_start_server',
            AdConfig.interstitialStartServer,
          );
        },
        onCreateProfile: () {
          Navigator.pop(ctx);
          _showCreateProfileThenStartSheet(defaultPort: defaultPort);
        },
      ),
    );
  }

  void _showCreateProfileThenStartSheet({int defaultPort = 8080}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Profile name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<ProfileBloc>().add(CreateProfileEvent(name: name));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _StartProfileSheet extends StatefulWidget {
  final List<Profile> profiles;
  final Set<String> runningProfileIds;
  final int defaultPort;
  final bool defaultUseDeviceIp;
  final String? initialProfileId;
  final void Function(String profileId, String profileName, int port, bool useDeviceIp, String? passThroughUrl, bool autoPassThrough) onStart;
  final VoidCallback? onCreateProfile;

  const _StartProfileSheet({
    required this.profiles,
    required this.onStart,
    this.runningProfileIds = const {},
    this.defaultPort = 8080,
    this.defaultUseDeviceIp = false,
    this.initialProfileId,
    this.onCreateProfile,
  });

  @override
  State<_StartProfileSheet> createState() => _StartProfileSheetState();
}

class _StartProfileSheetState extends State<_StartProfileSheet> {
  String? _selectedProfileId;
  late TextEditingController _portController;
  late bool _useDeviceIp;
  bool _autoPassThrough = false;
  late TextEditingController _passThroughUrlController;

  List<Profile> get _availableProfiles =>
      widget.profiles.where((p) => !widget.runningProfileIds.contains(p.id)).toList();

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: widget.defaultPort.toString());
    _useDeviceIp = widget.defaultUseDeviceIp;
    final available = _availableProfiles;
    if (available.isNotEmpty) {
      final initial = widget.initialProfileId != null
          ? available.firstWhere(
              (p) => p.id == widget.initialProfileId,
              orElse: () => available.first,
            )
          : available.first;
      _selectedProfileId = initial.id;
      _autoPassThrough = initial.settings.autoPassThrough;
      _passThroughUrlController = TextEditingController(
        text: initial.settings.globalPassThroughUrl ?? '',
      );
    } else {
      _passThroughUrlController = TextEditingController();
    }
  }

  void _onProfileSelected(String? profileId) {
    if (profileId == null) return;
    final profile = widget.profiles.firstWhere((p) => p.id == profileId);
    setState(() {
      _selectedProfileId = profileId;
      _autoPassThrough = profile.settings.autoPassThrough;
      _passThroughUrlController.text = profile.settings.globalPassThroughUrl ?? '';
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    _passThroughUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableProfiles;
    final allRunning = available.isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Start Server', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (allRunning) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: const Text(
                'All profiles are already running. Create a new profile to start another server instance.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create New Profile'),
              onPressed: widget.onCreateProfile,
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Profile',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedProfileId,
              items: available
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: (val) => _onProfileSelected(val),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
                helperText: 'Each running profile must use a unique port',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Use Device IP'),
              subtitle: const Text('Allow other devices to connect'),
              value: _useDeviceIp,
              onChanged: (val) => setState(() => _useDeviceIp = val),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Auto Pass-Through'),
              subtitle: const Text('Forward unmatched requests to base URL'),
              value: _autoPassThrough,
              onChanged: (val) => setState(() => _autoPassThrough = val),
              contentPadding: EdgeInsets.zero,
            ),
            if (_autoPassThrough) ...[
              TextField(
                controller: _passThroughUrlController,
                decoration: const InputDecoration(
                  labelText: 'Pass-Through Base URL',
                  border: OutlineInputBorder(),
                  hintText: 'https://api.example.com',
                  helperText: 'Unmatched requests forward to: base_url + path',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _selectedProfileId == null ? null : () {
                final port = int.tryParse(_portController.text) ?? widget.defaultPort;
                final profile = widget.profiles.firstWhere((p) => p.id == _selectedProfileId);
                final url = _autoPassThrough && _passThroughUrlController.text.trim().isNotEmpty
                    ? _passThroughUrlController.text.trim()
                    : null;
                widget.onStart(_selectedProfileId!, profile.name, port, _useDeviceIp, url, _autoPassThrough);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Start'),
            ),
            if (widget.onCreateProfile != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Or create a new profile'),
                onPressed: widget.onCreateProfile,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

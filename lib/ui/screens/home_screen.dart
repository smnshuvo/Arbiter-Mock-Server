import 'dart:async';
import 'dart:io';

import 'package:arbiter_mock_server/core/ads/ad_config.dart';
import 'package:arbiter_mock_server/core/ads/ad_service.dart';
import 'package:arbiter_mock_server/core/theme/theme_cubit.dart';
import 'package:arbiter_mock_server/core/services/file_server_service.dart';
import 'package:arbiter_mock_server/core/services/foreground_service.dart';
import 'package:arbiter_mock_server/core/services/overlay_service.dart';
import 'package:arbiter_mock_server/core/services/menu_bar_activity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme_data.dart';
import '../../domain/entities/interception_mode.dart';
import '../../domain/entities/network_condition.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/prompt.dart';
import '../../domain/repositories/endpoint_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../bloc/dependency_container.dart';
import '../bloc/endpoint/endpoint_bloc.dart';
import '../bloc/interception/interception_bloc.dart';
import '../bloc/interception/interception_event.dart';
import '../bloc/interception/interception_state.dart';
import '../bloc/prompt/prompt_bloc.dart';
import '../bloc/prompt/prompt_event.dart';
import '../bloc/prompt/prompt_state.dart';
import '../bloc/profile/profile_bloc.dart';
import '../bloc/server/server_bloc.dart';
import '../core/breakpoints.dart';
import '../dialog/interception_dialog.dart';
import '../dialog/prompt_resolution_dialog.dart';
import 'desktop/desktop_workspace_screen.dart';
import '../widgets/glowing_icon_widget.dart';
import '../widgets/grey_out_icon_widget.dart';
import 'file_server_screen.dart';
import 'mobile/mobile_endpoints_screen.dart';
import 'mobile/mobile_logs_screen.dart';
import 'mobile/start_profile_sheet.dart';
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

  /// Per-profile endpoint counts, shown on each server card. Loaded lazily
  /// (best-effort) whenever the profile list changes or we return from the
  /// endpoints screen.
  Map<String, int> _endpointCounts = {};
  bool _loadingCounts = false;
  bool _countsReloadQueued = false;

  /// Whether the server list is expanded past [_collapsedServerCount].
  bool _showAllServers = false;

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

    // Floating overlay live activity (Android) and macOS menu bar Live Activity —
    // both drive the existing blocs. They share the same control surface, so the
    // callbacks are wired to both native services.
    OverlayService.initialize();
    MenuBarActivityService.initialize();
    Future<bool> stopServer() async {
      if (!mounted) return false;
      final serverState = context.read<ServerBloc>().state;
      context.read<ServerBloc>().add(
            serverState is MultiServerRunning
                ? StopAllProfilesEvent()
                : StopServerEvent(),
          );
      return true;
    }

    OverlayService.onStopServerRequested = stopServer;
    MenuBarActivityService.onStopServerRequested = stopServer;

    void continueInterception(String id) {
      if (mounted) {
        context.read<InterceptionBloc>().add(ContinueWithoutModificationEvent(id));
      }
    }

    OverlayService.onInterceptionContinue = continueInterception;
    MenuBarActivityService.onInterceptionContinue = continueInterception;

    void dropInterception(String id) {
      if (mounted) {
        context.read<InterceptionBloc>().add(CancelInterceptionEvent(id));
      }
    }

    OverlayService.onInterceptionDrop = dropInterception;
    MenuBarActivityService.onInterceptionDrop = dropInterception;

    OverlayService.onPromptCandidateSelected = _useCandidateFromNative;
    MenuBarActivityService.onPromptCandidateSelected = _useCandidateFromNative;

    // Android overlay extras: open logs and toggle interception directly.
    OverlayService.onOpenLogs = () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MobileLogsScreen()),
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
    // macOS "Edit" opens the full interception dialog. The native side already brings
    // the app forward, and the dialog auto-opens on a pending intercept (see the
    // InterceptionPending listener below), so no extra Dart action is needed.

    print('HomeScreen: Callback set successfully');
    print('HomeScreen: Checking server status');
    context.read<ServerBloc>().add(CheckServerStatusEvent());
    print('HomeScreen: Starting interception watcher');
    context.read<InterceptionBloc>().add(StartWatchingInterceptions());
    context.read<PromptBloc>().add(StartWatchingPrompts());
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
  bool _promptDialogOpen = false;

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

  void _showPromptDialog(PromptActive state) {
    _promptDialogOpen = true;
    final dismissedId = state.prompt.id;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BlocProvider.value(
        value: context.read<PromptBloc>(),
        child: PromptResolutionDialog(prompt: state.prompt),
      ),
    ).then((_) {
      _promptDialogOpen = false;
      if (!mounted) return;
      // A different prompt may already be active by the time this dialog
      // finishes closing (it was queued behind the one just dismissed) — but
      // right after resolving, the bloc often hasn't processed that resolve
      // event yet, so `state` here can still be the SAME prompt we just
      // answered. Only re-show if the id actually differs, or an
      // already-resolved prompt reopens itself right after being answered.
      final current = context.read<PromptBloc>().state;
      if (current is PromptActive &&
          current.prompt.id != dismissedId &&
          _isForeground) {
        _showPromptDialog(current);
      }
    });
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
      final promptState = context.read<PromptBloc>().state;
      if (promptState is PromptActive && !_promptDialogOpen) {
        _showPromptDialog(promptState);
      }
    } else if (state == AppLifecycleState.paused) {
      _isForeground = false;
      // Arbiter went to the background: float the overlay over the foreground app.
      _syncOverlay(context.read<ServerBloc>().state);
    }
  }

  final MenuBarActivityService _menuBar = MenuBarActivityService();

  /// Reflects server start/stop in the macOS menu bar Live Activity (no-op elsewhere).
  void _syncMenuBarStatus(ServerState state) {
    if (state is ServerRunning) {
      _menuBar.show();
      _menuBar.updateStatus(
        running: true,
        address: Uri.tryParse(state.url)?.host ?? 'localhost',
        port: state.port,
      );
    } else if (state is MultiServerRunning && state.runningServers.isNotEmpty) {
      final first = state.runningServers.first;
      _menuBar.show();
      _menuBar.updateStatus(
        running: true,
        address: Uri.tryParse(first.url)?.host ?? 'localhost',
        port: first.port,
      );
    } else if (state is ServerStopped || state is ServerInitial) {
      _menuBar.hide();
    }
  }

  /// Flips the menu bar surface to/from the intercepted call-to-action.
  void _syncMenuBarInterception(InterceptionState state) {
    if (state is InterceptionPending) {
      final i = state.interception;
      _menuBar.setIntercepted(
        id: i.id,
        type: i.isResponse ? 'response' : 'request',
        method: i.method,
        url: i.url,
        statusCode: i.isResponse ? i.statusCode : null,
        body: i.isResponse ? i.responseBody : i.body,
      );
    } else {
      _menuBar.clearIntercepted();
    }
  }

  List<Map<String, dynamic>> _candidateArgs(PendingPrompt prompt) => [
        for (final c in prompt.candidates)
          {'id': c.id, 'label': c.label, 'statusCode': c.statusCode, 'body': c.body},
      ];

  /// Flips the floating overlay to/from a live "Prompt" candidate picker, so
  /// a response can be chosen right from the overlay when Arbiter isn't the
  /// focused window — not just a generic "waiting" indicator.
  void _syncOverlayPrompt(PromptState state) {
    if (state is PromptActive) {
      final p = state.prompt;
      _overlay.setPrompt(
        id: p.id,
        method: p.method,
        url: p.path,
        candidates: _candidateArgs(p),
      );
    } else {
      _overlay.clearPrompt();
    }
  }

  /// Menu bar counterpart of [_syncOverlayPrompt].
  void _syncMenuBarPrompt(PromptState state) {
    if (state is PromptActive) {
      final p = state.prompt;
      _menuBar.setPrompt(
        id: p.id,
        method: p.method,
        url: p.path,
        candidates: _candidateArgs(p),
      );
    } else {
      _menuBar.clearPrompt();
    }
  }

  /// A candidate was picked directly from the overlay/menu bar picker.
  void _useCandidateFromNative(String promptId, String candidateId) {
    if (!mounted) return;
    final state = context.read<PromptBloc>().state;
    if (state is! PromptActive || state.prompt.id != promptId) return;
    for (final candidate in state.prompt.candidates) {
      if (candidate.id == candidateId) {
        context.read<PromptBloc>().add(UsePromptCandidateEvent(promptId, candidate));
        return;
      }
    }
  }

  Future<bool> _checkAndRequestNotificationPermission() async {
    // Notification permission only gates the Android foreground service.
    // permission_handler isn't implemented on other platforms, so skip it.
    if (!Platform.isAndroid) {
      return true;
    }

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
    // A change landing mid-load would otherwise be dropped and leave a stale
    // count, so remember it and run once more when the current load finishes.
    if (_loadingCounts) {
      _countsReloadQueued = true;
      return;
    }
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
    if (_countsReloadQueued && mounted) {
      _countsReloadQueued = false;
      final profileState = context.read<ProfileBloc>().state;
      if (profileState is ProfileLoaded) _loadEndpointCounts(profileState.profiles);
    }
  }

  /// Opens a profile's endpoints. The id is handed to the screen directly —
  /// the `SwitchActiveProfileEvent` below only keeps the rest of the app in
  /// sync and lands too late to be read as the destination (see
  /// [MobileEndpointsScreen]).
  Future<void> _openEndpoints(Profile profile) async {
    context.read<ProfileBloc>().add(SwitchActiveProfileEvent(profile.id));
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MobileEndpointsScreen(profileId: profile.id)),
    );
    if (!mounted) return;
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      _loadEndpointCounts(profileState.profiles);
    }
  }

  void _openLogs(Profile profile) {
    context.read<ProfileBloc>().add(SwitchActiveProfileEvent(profile.id));
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MobileLogsScreen(profileId: profile.id)),
    );
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
            _syncMenuBarStatus(state);
          },
          builder: (context, state) {
            return MultiBlocListener(
              listeners: [
                BlocListener<InterceptionBloc, InterceptionState>(
                  listener: (context, interceptionState) {
                    _syncOverlayInterception(interceptionState);
                    _syncMenuBarInterception(interceptionState);
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
                BlocListener<PromptBloc, PromptState>(
                  listener: (context, promptState) {
                    _syncOverlayPrompt(promptState);
                    _syncMenuBarPrompt(promptState);
                    if (promptState is PromptActive &&
                        _isForeground &&
                        !_promptDialogOpen) {
                      _showPromptDialog(promptState);
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
                // Endpoint create/update/delete/import all end in EndpointLoaded;
                // refresh the per-server counts (desktop rail, mobile cards).
                BlocListener<EndpointBloc, EndpointState>(
                  listenWhen: (_, current) => current is EndpointLoaded,
                  listener: (context, _) {
                    final profileState = context.read<ProfileBloc>().state;
                    if (profileState is ProfileLoaded) {
                      _loadEndpointCounts(profileState.profiles);
                    }
                  },
                ),
              ],
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > kWideLayoutBreakpoint) {
                    return DesktopWorkspaceScreen(
                      serverState: state,
                      endpointCounts: _endpointCounts,
                    );
                  }
                  return _buildContent(state);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(ServerState state) {
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
              const SizedBox(height: 20),
              if (profileState is! ProfileLoaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _buildServerList(profiles, running),
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
            MaterialPageRoute(builder: (context) => const MobileLogsScreen()),
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

  /// Vertical list of servers, one full-width terminal-styled card each.
  ///
  /// Every row carries its own Start/Stop button, so each action names the
  /// server it acts on — there is no "selected" card. The row has exactly one
  /// tap target beyond that button: anywhere on the card, as well as its
  /// "endpoints" CTA, opens that server's endpoints and nothing else. Past
  /// [_collapsedServerCount] the tail is folded behind a "show all" toggle so
  /// the screen stays scannable; a single "New server" row closes the list.
  Widget _buildServerList(
    List<Profile> profiles,
    Map<String, ({String url, int port})> running,
  ) {
    final collapsed = !_showAllServers && profiles.length > _collapsedServerCount;
    final visible = collapsed ? profiles.take(_collapsedServerCount) : profiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text('No servers yet',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          )
        else
          for (final profile in visible) ...[
            _serverCard(
              profile,
              running.containsKey(profile.id),
              address: _addressFor(profile.id, running),
              running: running,
            ),
            const SizedBox(height: 12),
          ],
        if (profiles.length > _collapsedServerCount) ...[
          _buildShowAllToggle(profiles.length, collapsed),
          const SizedBox(height: 12),
        ],
        _buildNewServerRow(),
      ],
    );
  }

  /// How many servers the list shows before folding the rest away.
  static const int _collapsedServerCount = 2;

  Widget _buildShowAllToggle(int total, bool collapsed) {
    final hidden = total - _collapsedServerCount;
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: () => setState(() => _showAllServers = !_showAllServers),
        icon: Icon(collapsed ? Icons.add_rounded : Icons.remove_rounded, size: 18),
        label: Text(collapsed ? 'Show all ($hidden more)' : 'Show less'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// "host:port" for a running profile — localhost or the LAN IP, whichever
  /// the server was actually bound to — or null while stopped.
  String? _addressFor(String profileId, Map<String, ({String url, int port})> running) {
    final info = running[profileId];
    if (info == null) return null;
    final host = Uri.tryParse(info.url)?.host;
    return '${host?.isNotEmpty == true ? host : 'localhost'}:${info.port}';
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $address'), duration: const Duration(seconds: 1)),
    );
  }

  /// One server as a terminal window: a macOS-style traffic-light title bar
  /// holding only the endpoints CTA, then inside the window the server name as
  /// a prompt line, a monospace port/address readout, status + endpoint count,
  /// and its own Start/Stop button. While running the readout becomes the
  /// actual bound address (localhost or LAN IP, whichever the server used)
  /// with a copy button.
  Widget _serverCard(
    Profile profile,
    bool isRunning, {
    String? address,
    required Map<String, ({String url, int port})> running,
  }) {
    final statusColor = isRunning ? const Color(0xFF2ECC71) : const Color(0xFF8B8F98);
    final showAddress = isRunning && address != null;
    final endpointCount = _endpointCounts[profile.id];
    final hasBadges = profile.settings.autoPassThrough ||
        profile.settings.networkCondition != NetworkCondition.none;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEndpoints(profile),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF1B1D23),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRunning
                  ? AppColors.running.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                ),
                child: Row(
                  children: [
                    _trafficDot(const Color(0xFFFF5F57)),
                    const SizedBox(width: 5),
                    _trafficDot(const Color(0xFFFEBC2E)),
                    const SizedBox(width: 5),
                    _trafficDot(const Color(0xFF28C840)),
                    const Spacer(),
                    _titleBarCta('logs', () => _openLogs(profile)),
                    const SizedBox(width: 6),
                    _titleBarCta('endpoints', () => _openEndpoints(profile)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The name reads as the window's first prompt line rather
                    // than a chrome title, so the terminal metaphor holds.
                    Text('>_ \$: ${profile.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoTextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 12),
                    Text(showAddress ? '\$ curl' : '\$ port',
                        style: monoTextStyle(fontSize: 10.5, color: Colors.white38)),
                    const SizedBox(height: 3),
                    if (showAddress)
                      Row(
                        children: [
                          Expanded(
                            // FittedBox rather than a fixed size + ellipsis: the
                            // full address must stay readable (and copyable)
                            // whatever the host string's length turns out to be.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(address,
                                  style: monoTextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _copyAddress(address),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.copy_rounded, size: 16, color: Colors.white54),
                            ),
                          ),
                        ],
                      )
                    else
                      Text('${profile.port}',
                          style: monoTextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration:
                              BoxDecoration(shape: BoxShape.circle, color: statusColor),
                        ),
                        const SizedBox(width: 6),
                        Text(isRunning ? 'active' : 'inactive',
                            style: monoTextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: statusColor)),
                        if (endpointCount != null) ...[
                          Text('  ·  ',
                              style: monoTextStyle(fontSize: 12, color: Colors.white24)),
                          Expanded(
                            child: Text(
                                '$endpointCount endpoint${endpointCount == 1 ? '' : 's'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: monoTextStyle(fontSize: 12, color: Colors.white38)),
                          ),
                        ],
                      ],
                    ),
                    if (hasBadges) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (profile.settings.autoPassThrough) _infoBadge('pass-through'),
                          if (profile.settings.networkCondition != NetworkCondition.none)
                            _infoBadge('throttled'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    _startStopButton(profile, isRunning, running),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Labelled call to action in the card's title bar. "endpoints" goes to the
  /// same place as a tap on the card body — captioning that gesture so the
  /// card doesn't rely on the user guessing it's tappable; "logs" opens that
  /// server's request log.
  Widget _titleBarCta(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: monoTextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent)),
              const SizedBox(width: 3),
              const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style:
              monoTextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.accent)),
    );
  }

  Widget _trafficDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  /// Per-card Start/Stop. Starting opens the same "Start server" sheet as the
  /// new-server flow, just with this profile pre-selected.
  Widget _startStopButton(Profile profile, bool isRunning,
      Map<String, ({String url, int port})> running) {
    return ElevatedButton.icon(
      onPressed: () {
        if (isRunning) {
          context.read<ServerBloc>().add(StopProfileEvent(profile.id));
        } else {
          final usedPorts = running.values.map((e) => e.port).toSet();
          _showStartProfileSheet(
            defaultPort: _nextFreePort(profile.port, usedPorts),
            defaultUseDeviceIp: profile.settings.useDeviceIp,
            initialProfileId: profile.id,
          );
        }
      },
      icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
      label: Text(isRunning ? 'Stop Server' : 'Start Server',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: isRunning ? AppColors.error : AppColors.running,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Closes the server list — the single create-server affordance. Goes
  /// straight to the name prompt: naming it is the only thing needed to get a
  /// server into the list, and everything else (port, host, pass-through) is
  /// decided later on its own card's Start button.
  Widget _buildNewServerRow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _showCreateProfileDialog,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded, size: 20, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('New server',
                    style: monoTextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent)),
              ],
            ),
          ),
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

    showStartProfileSheet(
      context: context,
      profiles: loaded.profiles,
      runningProfileIds: runningProfileIds,
      defaultPort: defaultPort,
      defaultUseDeviceIp: defaultUseDeviceIp,
      initialProfileId: initialProfileId,
      onStart: (profileId, profileName, port, useDeviceIp, passThroughUrl, autoPassThrough,
          networkCondition) async {
        final hasPermission = await _checkAndRequestNotificationPermission();
        if (!hasPermission || !mounted) return false;
        // Save what the sheet edited back to the profile so it persists — the
        // sheet now carries the same settings as the Manage sheet, so all of
        // them have to survive the start, not just the pass-through URL.
        final profile = loaded.profiles.firstWhere((p) => p.id == profileId);
        final updatedProfile = profile.copyWith(
          port: port,
          settings: profile.settings.copyWith(
            globalPassThroughUrl: passThroughUrl,
            clearPassThroughUrl: passThroughUrl == null,
            autoPassThrough: autoPassThrough,
            useDeviceIp: useDeviceIp,
            networkCondition: networkCondition,
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
          networkCondition: networkCondition,
        ));
        // Full-screen ad on server start, throttled to once per hour.
        sl<AdService>().maybeShowInterstitial(
          'ad_gate_start_server',
          AdConfig.interstitialStartServer,
        );
        return true;
      },
      onCreateProfile: _showCreateProfileDialog,
    );
  }

  /// The whole create-server flow: name it, and it lands in the list stopped,
  /// ready for its own Start button. Also reachable from the "Start server"
  /// sheet's create option.
  void _showCreateProfileDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Server'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Server name'),
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createProfileFrom(controller, ctx),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => _createProfileFrom(controller, ctx),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _createProfileFrom(TextEditingController controller, BuildContext dialogContext) {
    final name = controller.text.trim();
    if (name.isEmpty) return;
    context.read<ProfileBloc>().add(CreateProfileEvent(name: name));
    // A newly created server sits at the end of the list, so make sure it is
    // actually visible rather than hidden behind the "show all" fold.
    setState(() => _showAllServers = true);
    Navigator.pop(dialogContext);
  }
}


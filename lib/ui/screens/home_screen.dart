import 'package:arbiter_mock_server/core/theme/theme_cubit.dart';
import 'package:arbiter_mock_server/core/services/foreground_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/server_manager.dart';
import '../../domain/entities/interception_mode.dart';
import '../../domain/entities/profile.dart';
import '../bloc/interception/interception_bloc.dart';
import '../bloc/interception/interception_event.dart';
import '../bloc/interception/interception_state.dart';
import '../bloc/profile/profile_bloc.dart';
import '../bloc/server/server_bloc.dart';
import '../dialog/interception_dialog.dart';
import '../widgets/glowing_icon_widget.dart';
import '../widgets/grey_out_icon_widget.dart';
import 'endpoint_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

typedef _RunningServerInfo = RunningServerInfo;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _portController =
      TextEditingController(text: '8080');

  static const iconAssetPath = 'assets/app_icon/app_icon.png';
  static const sunIconAssetPath = 'assets/sun.png';
  static const moonIconAssetPath = 'assets/moon.png';

  @override
  void initState() {
    super.initState();
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
    
    // Live Activity notification actions → drive the existing blocs.
    ForegroundService.onInterceptionContinue = (id) {
      if (mounted) {
        context.read<InterceptionBloc>().add(ContinueWithoutModificationEvent(id));
      }
    };
    ForegroundService.onInterceptionDrop = (id) {
      if (mounted) {
        context.read<InterceptionBloc>().add(CancelInterceptionEvent(id));
      }
    };
    // "Edit" foregrounds the app; the InterceptionPending listener below already
    // auto-opens the full dialog, so no extra action is needed here.
    ForegroundService.onInterceptionEdit = (_) {};
    ForegroundService.onOpenLogs = () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LogsScreen()),
        );
      }
    };

    print('HomeScreen: Callback set successfully');
    print('HomeScreen: Checking server status');
    context.read<ServerBloc>().add(CheckServerStatusEvent());
    print('HomeScreen: Starting interception watcher');
    context.read<InterceptionBloc>().add(StartWatchingInterceptions());
    print('HomeScreen: ============================================');
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  final ForegroundService _foregroundService = ForegroundService();

  /// Pushes server start/stop into the Android Live Activity notification header.
  void _syncLiveActivityStatus(ServerState state) {
    if (state is ServerRunning) {
      _foregroundService.setServerStatus(
        address: Uri.tryParse(state.url)?.host ?? 'localhost',
        port: state.port,
      );
    } else if (state is MultiServerRunning && state.runningServers.isNotEmpty) {
      final first = state.runningServers.first;
      _foregroundService.setServerStatus(
        address: Uri.tryParse(first.url)?.host ?? 'localhost',
        port: first.port,
      );
    }
  }

  /// Flips the Live Activity notification to/from the intercepted call-to-action.
  void _syncLiveActivityInterception(InterceptionState state) {
    if (state is InterceptionPending) {
      final i = state.interception;
      _foregroundService.setIntercepted(
        id: i.id,
        type: i.isResponse ? 'response' : 'request',
        method: i.method,
        url: i.url,
        statusCode: i.isResponse ? i.statusCode : null,
        body: i.isResponse ? i.responseBody : i.body,
      );
    } else {
      _foregroundService.clearIntercepted();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbiter'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
          BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (context, themeMode) {
              return Switch(
                value: themeMode == ThemeMode.dark,
                onChanged: (_) => context.read<ThemeCubit>().toggleTheme(),
                activeThumbImage: const AssetImage(moonIconAssetPath),
                inactiveThumbImage: const AssetImage(sunIconAssetPath),
              );
            },
          )
        ],
      ),
      body: BlocConsumer<ServerBloc, ServerState>(
        listener: (context, state) {
          if (state is ServerError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
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

          _syncLiveActivityStatus(state);
        },
        builder: (context, state) {
          return BlocListener<InterceptionBloc, InterceptionState>(
            listener: (context, interceptionState) {
              _syncLiveActivityInterception(interceptionState);
              if (interceptionState is InterceptionPending) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => BlocProvider.value(
                    value: context.read<InterceptionBloc>(),
                    child: InterceptionDialog(
                      interception: interceptionState.interception,
                      timeoutSeconds: interceptionState.timeoutSeconds,
                    ),
                  ),
                );
              }
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildServerStatusCard(state),
                  const SizedBox(height: 16),
                  _buildPortConfiguration(state),
                  const SizedBox(height: 16),
                  _buildInterceptionConfig(state),
                  const SizedBox(height: 24),
                  _buildNavigationButtons(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildServerStatusCard(ServerState state) {
    if (state is MultiServerRunning) {
      return _buildMultiServerCard(state);
    }

    final isRunning = state is ServerRunning;
    final isLoading = state is ServerLoading;
    final runningState = state is ServerRunning ? state : null;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            isRunning
                ? const GlowingIconWidget(
                    iconAssetPath: iconAssetPath,
                    size: 64,
                    glowColor: Colors.green,
                  )
                : const GreyOutIconWidget(
                    iconAssetPath: iconAssetPath,
                    size: 64.0,
                    opacity: 0.5,
                    greyIntensity: 1.0,
                  ),
            const SizedBox(height: 16),
            Text(
              isRunning ? 'Server Running' : 'Server Stopped',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (state is ServerRunning) ...[
              const SizedBox(height: 8),
              Text(
                state.url,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: state.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL copied to clipboard')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy URL'),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (isRunning && runningState != null) {
                        context.read<ServerBloc>().add(
                          StopProfileEvent(runningState.profileId),
                        );
                      } else if (!isRunning) {
                        final hasPermission = await _checkAndRequestNotificationPermission();
                        if (!hasPermission) return;

                        final stoppedState = state is ServerStopped ? state : null;
                        final defaultPort = int.tryParse(_portController.text) ?? 8080;
                        _showStartProfileSheet(
                          defaultPort: defaultPort,
                          defaultUseDeviceIp: stoppedState?.useDeviceIp ?? false,
                        );
                      }
                    },
              icon: Icon(
                isRunning ? Icons.stop : Icons.play_arrow,
                color: Colors.white,
              ),
              label: Text(
                isRunning ? 'Stop Server' : 'Start Server',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? Colors.red : Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            if (isRunning) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Start Another Profile'),
                onPressed: () {
                  _showStartProfileSheet(defaultPort: (runningState?.port ?? 8080) + 1);
                },
              ),
            ],
            if (!isRunning && state is ServerStopped) ...[
              const SizedBox(height: 16),
              _buildDeviceIpToggle(state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMultiServerCard(MultiServerRunning state) {
    final servers = state.runningServers;
    const maxVisible = 3;
    final showSeeAll = servers.length > maxVisible;
    final visibleServers = showSeeAll ? servers.take(maxVisible).toList() : servers;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const GlowingIconWidget(
                  iconAssetPath: iconAssetPath,
                  size: 48,
                  glowColor: Colors.green,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Multiple Profiles Running',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${servers.length} active',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                  label: const Text('Stop All', style: TextStyle(color: Colors.red)),
                  onPressed: () => context.read<ServerBloc>().add(StopAllProfilesEvent()),
                ),
              ],
            ),
            const Divider(height: 20),
            ...visibleServers.map((srv) => _buildRunningProfileRow(srv)),
            if (showSeeAll) ...[
              const SizedBox(height: 4),
              _SeeAllExpander(allServers: servers, visibleCount: maxVisible),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Start Another Profile'),
                onPressed: () {
                  final usedPorts = state.runningServers.map((s) => s.port).toSet();
                  int nextPort = 8080;
                  while (usedPorts.contains(nextPort)) nextPort++;
                  _showStartProfileSheet(defaultPort: nextPort, defaultUseDeviceIp: false);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunningProfileRow(_RunningServerInfo srv) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: Colors.green[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(srv.profileName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(srv.url, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy URL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: srv.url));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied'), duration: Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.red),
            tooltip: 'Stop profile',
            onPressed: () => context.read<ServerBloc>().add(StopProfileEvent(srv.profileId)),
          ),
        ],
      ),
    );
  }

  void _showStartProfileSheet({int defaultPort = 8080, bool defaultUseDeviceIp = false}) {
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is! ProfileLoaded) return;

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
        profiles: profileState.profiles,
        runningProfileIds: runningProfileIds,
        defaultPort: defaultPort,
        defaultUseDeviceIp: defaultUseDeviceIp,
        onStart: (profileId, profileName, port, useDeviceIp, passThroughUrl, autoPassThrough) {
          Navigator.pop(ctx);
          // Save pass-through settings back to the profile so the URL persists
          final profile = profileState.profiles.firstWhere((p) => p.id == profileId);
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

  Widget _buildDeviceIpToggle(ServerStopped state) {
    return Card(
      color: Theme.of(context).highlightColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.wifi, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Use Device IP',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.useDeviceIp && state.deviceIp != null
                        ? 'Server will be accessible at: ${state.deviceIp}:${state.port}'
                        : 'Allow other devices to connect',
                    style: const TextStyle(
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: state.useDeviceIp,
              onChanged: (value) {
                context.read<ServerBloc>().add(SetUseDeviceIpEvent(value));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortConfiguration(ServerState state) {
    if (state is MultiServerRunning) return const SizedBox.shrink();
    final isRunning = state is ServerRunning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Server Port',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              enabled: !isRunning,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Port',
                hintText: '8080',
                suffixIcon: isRunning
                    ? const Icon(Icons.lock, color: Colors.grey)
                    : null,
              ),
              onChanged: (value) {
                final port = int.tryParse(value);
                if (port != null && !isRunning) {
                  context.read<ServerBloc>().add(SetServerPortEvent(port));
                }
              },
            ),
            if (isRunning)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Stop the server to change the port',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterceptionConfig(ServerState state) {
    return BlocBuilder<InterceptionBloc, InterceptionState>(
      builder: (context, interceptionState) {
        final mode = interceptionState is InterceptionEnabled
            ? interceptionState.mode
            : (interceptionState is InterceptionPending
                ? interceptionState.mode
                : InterceptionMode.none);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Real-time Interception',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (interceptionState is InterceptionPending)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'PENDING',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Pause requests for manual inspection',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: mode != InterceptionMode.none,
                      onChanged: (value) {
                        context.read<InterceptionBloc>().add(
                              SetInterceptionModeEvent(
                                value
                                    ? InterceptionMode.both
                                    : InterceptionMode.none,
                              ),
                            );
                      },
                    ),
                  ],
                ),
                if (mode != InterceptionMode.none) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Interception Mode',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<InterceptionMode>(
                    value: mode,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      InterceptionMode.requestOnly,
                      InterceptionMode.responseOnly,
                      InterceptionMode.both,
                    ]
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m.displayName),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        context.read<InterceptionBloc>().add(
                              SetInterceptionModeEvent(value),
                            );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).highlightColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Requests will pause for 30 seconds allowing you to inspect and modify them',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigationButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EndpointsScreen()),
            );
          },
          icon: const Icon(Icons.settings_ethernet),
          label: const Text('Manage Endpoints'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LogsScreen()),
            );
          },
          icon: const Icon(Icons.list_alt),
          label: const Text('View Logs'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _SeeAllExpander extends StatefulWidget {
  final List<RunningServerInfo> allServers;
  final int visibleCount;

  const _SeeAllExpander({required this.allServers, required this.visibleCount});

  @override
  State<_SeeAllExpander> createState() => _SeeAllExpanderState();
}

class _SeeAllExpanderState extends State<_SeeAllExpander> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (_expanded) {
      return Column(
        children: [
          ...widget.allServers.skip(widget.visibleCount).map((srv) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: Colors.green[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(srv.profileName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(srv.url, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy URL',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: srv.url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL copied'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.red),
                  tooltip: 'Stop profile',
                  onPressed: () => context.read<ServerBloc>().add(StopProfileEvent(srv.profileId)),
                ),
              ],
            ),
          )),
          TextButton(
            onPressed: () => setState(() => _expanded = false),
            child: const Text('Show less'),
          ),
        ],
      );
    }

    return TextButton(
      onPressed: () => setState(() => _expanded = true),
      child: Text('See all (${widget.allServers.length})'),
    );
  }
}

class _StartProfileSheet extends StatefulWidget {
  final List<Profile> profiles;
  final Set<String> runningProfileIds;
  final int defaultPort;
  final bool defaultUseDeviceIp;
  final void Function(String profileId, String profileName, int port, bool useDeviceIp, String? passThroughUrl, bool autoPassThrough) onStart;
  final VoidCallback? onCreateProfile;

  const _StartProfileSheet({
    required this.profiles,
    required this.onStart,
    this.runningProfileIds = const {},
    this.defaultPort = 8080,
    this.defaultUseDeviceIp = false,
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
      _selectedProfileId = available.first.id;
      _autoPassThrough = available.first.settings.autoPassThrough;
      _passThroughUrlController = TextEditingController(
        text: available.first.settings.globalPassThroughUrl ?? '',
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
              value: _selectedProfileId,
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

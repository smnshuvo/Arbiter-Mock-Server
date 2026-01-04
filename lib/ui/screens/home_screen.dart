import 'package:arbiter_mock_server/core/theme/theme_cubit.dart';
import 'package:arbiter_mock_server/core/services/foreground_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/entities/interception_mode.dart';
import '../bloc/interception/interception_bloc.dart';
import '../bloc/interception/interception_event.dart';
import '../bloc/interception/interception_state.dart';
import '../bloc/server/server_bloc.dart';
import '../dialog/interception_dialog.dart';
import '../widgets/glowing_icon_widget.dart';
import '../widgets/grey_out_icon_widget.dart';
import 'endpoint_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _portController =
      TextEditingController(text: '8080');
  final TextEditingController _passThroughUrlController =
      TextEditingController();

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
    _passThroughUrlController.dispose();
    super.dispose();
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
          }

          // Update pass-through URL controller when state changes
          if (state is ServerRunning || state is ServerStopped) {
            final url = state is ServerRunning
                ? state.globalPassThroughUrl
                : (state as ServerStopped).globalPassThroughUrl;
            if (url != null && url != _passThroughUrlController.text) {
              _passThroughUrlController.text = url;
            }
          }

          // Stop foreground service when server stops
          if (state is ServerStopped) {
            print('HomeScreen: Server stopped, stopping foreground service');
            ForegroundService().stopForegroundService();
          }
        },
        builder: (context, state) {
          return BlocListener<InterceptionBloc, InterceptionState>(
            listener: (context, interceptionState) {
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
                  _buildAutoPassThroughConfig(state),
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
    final isRunning = state is ServerRunning;
    final isLoading = state is ServerLoading;

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
                      if (isRunning) {
                        context.read<ServerBloc>().add(StopServerEvent());
                      } else {
                        // Check notification permission before starting server
                        final hasPermission = await _checkAndRequestNotificationPermission();
                        
                        if (!hasPermission) {
                          return; // Don't start server if permission not granted
                        }
                        
                        final port = int.tryParse(_portController.text) ?? 8080;
                        final useDeviceIp = state is ServerStopped
                            ? (state as ServerStopped).useDeviceIp
                            : false;
                        context.read<ServerBloc>().add(
                              StartServerEvent(port, useDeviceIp: useDeviceIp),
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
            if (!isRunning && state is ServerStopped) ...[
              const SizedBox(height: 16),
              _buildDeviceIpToggle(state as ServerStopped),
            ],
          ],
        ),
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

  Widget _buildAutoPassThroughConfig(ServerState state) {
    final isRunning = state is ServerRunning;
    final autoPassThrough = state is ServerRunning
        ? state.autoPassThrough
        : (state is ServerStopped ? state.autoPassThrough : false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto Pass-Through',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Forward unmatched requests to base URL',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: autoPassThrough,
                  onChanged: (value) {
                    context
                        .read<ServerBloc>()
                        .add(SetAutoPassThroughEvent(value));
                  },
                ),
              ],
            ),
            if (autoPassThrough) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _passThroughUrlController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Global Pass-Through Base URL',
                  hintText: 'https://api.example.com',
                  helperText:
                      'Requests will be forwarded as: base_url + request_path',
                  suffixIcon: isRunning
                      ? const Icon(Icons.lock, color: Colors.grey)
                      : null,
                ),
                enabled: !isRunning,
                onChanged: (value) {
                  context
                      .read<ServerBloc>()
                      .add(SetGlobalPassThroughUrlEvent(value));
                },
              ),
              if (isRunning)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Stop the server to change the pass-through URL',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
            ],
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

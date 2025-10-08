import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/server/server_bloc.dart';
import 'endpoint_screen.dart';
import 'logs_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _portController =
      TextEditingController(text: '8080');
  final TextEditingController _passThroughUrlController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<ServerBloc>().add(CheckServerStatusEvent());
  }

  @override
  void dispose() {
    _portController.dispose();
    _passThroughUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Interceptor'),
        centerTitle: true,
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
        },
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildServerStatusCard(state),
                const SizedBox(height: 16),
                _buildPortConfiguration(state),
                const SizedBox(height: 16),
                _buildAutoPassThroughConfig(state),
                const SizedBox(height: 24),
                _buildNavigationButtons(),
              ],
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
            Icon(
              isRunning ? Icons.check_circle : Icons.cancel,
              size: 64,
              color: isRunning ? Colors.green : Colors.grey,
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
                  : () {
                      if (isRunning) {
                        context.read<ServerBloc>().add(StopServerEvent());
                      } else {
                        final port = int.tryParse(_portController.text) ?? 8080;
                        context.read<ServerBloc>().add(StartServerEvent(port));
                      }
                    },
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(isRunning ? 'Stop Server' : 'Start Server'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRunning ? Colors.red : Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
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

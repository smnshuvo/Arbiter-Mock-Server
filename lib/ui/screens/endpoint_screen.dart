import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/endpoint.dart';
import '../bloc/endpoint/endpoint_bloc.dart';
import 'endpoint_form_screen.dart';

class EndpointsScreen extends StatefulWidget {
  const EndpointsScreen({super.key});

  @override
  State<EndpointsScreen> createState() => _EndpointsScreenState();
}

class _EndpointsScreenState extends State<EndpointsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<EndpointBloc>().add(LoadEndpointsEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Endpoints'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _importEndpoints,
            tooltip: 'Import',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportEndpoints,
            tooltip: 'Export',
          ),
        ],
      ),
      body: BlocConsumer<EndpointBloc, EndpointState>(
        listener: (context, state) {
          if (state is EndpointError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is EndpointExported) {
            _saveAndShareExport(state.jsonData);
          }
        },
        builder: (context, state) {
          if (state is EndpointLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is EndpointLoaded) {
            if (state.endpoints.isEmpty) {
              return _buildEmptyState();
            }
            return _buildEndpointList(state.endpoints);
          }

          return const SizedBox();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EndpointFormScreen(),
            ),
          );
          context.read<EndpointBloc>().add(LoadEndpointsEvent());
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings_ethernet,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No endpoints configured',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add an endpoint',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointList(List<Endpoint> endpoints) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        return _buildEndpointCard(endpoint);
      },
    );
  }

  Widget _buildEndpointCard(Endpoint endpoint) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: Icon(
          endpoint.mode == EndpointMode.mock ? Icons.code : Icons.swap_horiz,
          color: endpoint.isEnabled ? Colors.blue : Colors.grey,
        ),
        title: Text(
          endpoint.pattern,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: endpoint.isEnabled ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                _buildChip(
                  endpoint.mode == EndpointMode.mock ? 'Mock' : 'Pass-through',
                  endpoint.mode == EndpointMode.mock ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                _buildChip(
                  endpoint.matchType.name.toUpperCase(),
                  Colors.blue,
                ),
                if (endpoint.mode == EndpointMode.mock) ...[
                  const SizedBox(width: 8),
                  _buildChip(
                    _getStatusCodeText(endpoint.statusCode),
                    _getStatusCodeColor(endpoint.statusCode),
                  ),
                ],
                if (endpoint.delayMs > 0) ...[
                  const SizedBox(width: 8),
                  _buildChip(
                    '${endpoint.delayMs}ms',
                    Colors.purple,
                  ),
                ],
                if (endpoint.useConditionalMock && endpoint.conditionalMocks.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildChip(
                    '${endpoint.conditionalMocks.length} Conditions',
                    Colors.teal,
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Switch(
          value: endpoint.isEnabled,
          onChanged: (value) {
            final updated = endpoint.copyWith(
              isEnabled: value,
              updatedAt: DateTime.now(),
            );
            context.read<EndpointBloc>().add(UpdateEndpointEvent(updated));
          },
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EndpointFormScreen(endpoint: endpoint),
            ),
          );
          context.read<EndpointBloc>().add(LoadEndpointsEvent());
        },
        onLongPress: () => _showDeleteDialog(endpoint),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getStatusCodeText(int code) {
    if (code >= 200 && code < 300) {
      return '$code';
    } else if (code >= 400 && code < 500) {
      return '$code';
    } else if (code >= 500) {
      return '$code';
    }
    return '$code';
  }

  Color _getStatusCodeColor(int code) {
    if (code >= 200 && code < 300) {
      return Colors.green;
    } else if (code >= 400 && code < 500) {
      return Colors.orange;
    } else if (code >= 500) {
      return Colors.red;
    }
    return Colors.grey;
  }

  void _showDeleteDialog(Endpoint endpoint) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Endpoint'),
          content: Text('Are you sure you want to delete "${endpoint.pattern}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context.read<EndpointBloc>().add(DeleteEndpointEvent(endpoint.id));
                Navigator.pop(dialogContext);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importEndpoints() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final jsonData = jsonDecode(jsonString);

        final endpointsJson = jsonData['endpoints'] as List;
        final endpoints = endpointsJson
            .map((json) => _jsonToEndpoint(json))
            .toList();

        if (mounted) {
          context.read<EndpointBloc>().add(ImportEndpointsEvent(endpoints));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${endpoints.length} endpoints')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportEndpoints() async {
    context.read<EndpointBloc>().add(ExportEndpointsEvent());
  }

  Future<void> _saveAndShareExport(String jsonData) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/endpoints_export.json');
      await file.writeAsString(jsonData);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Network Interceptor Endpoints Export',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export successful')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Endpoint _jsonToEndpoint(Map<String, dynamic> json) {
    return Endpoint(
      id: json['id'],
      pattern: json['pattern'],
      matchType: MatchType.values.firstWhere((e) => e.name == json['matchType']),
      mode: EndpointMode.values.firstWhere((e) => e.name == json['mode']),
      mockResponse: json['mockResponse'],
      statusCode: json['statusCode'] ?? 200,
      delayMs: json['delayMs'],
      targetUrl: json['targetUrl'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      isEnabled: json['isEnabled'] == 1,
    );
  }
}
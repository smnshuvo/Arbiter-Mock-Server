import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/endpoint.dart';
import '../../domain/entities/request_log.dart';
import '../../domain/repositories/log_repository.dart';
import '../bloc/log/log_bloc.dart';
import '../widgets/json_viewer_widget.dart';
import 'endpoint_form_screen.dart';
import 'log_filter_screen.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({Key? key}) : super(key: key);

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final TextEditingController _searchController = TextEditingController();
  LogFilter? _currentFilter;

  @override
  void initState() {
    super.initState();
    context.read<LogBloc>().add(LoadLogsEvent());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportLogs,
            tooltip: 'Export',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear_all') {
                _showClearDialog(false);
              } else if (value == 'clear_filtered') {
                _showClearDialog(true);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: Text('Clear All Logs'),
              ),
              const PopupMenuItem(
                value: 'clear_filtered',
                child: Text('Clear Filtered Logs'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_currentFilter != null) _buildFilterChips(),
          Expanded(
            child: BlocConsumer<LogBloc, LogState>(
              listener: (context, state) {
                if (state is LogError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else if (state is LogExported) {
                  _saveAndShareExport(state.jsonData);
                }
              },
              builder: (context, state) {
                if (state is LogLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is LogLoaded) {
                  if (state.logs.isEmpty) {
                    return _buildEmptyState();
                  }
                  return _buildLogList(state.logs);
                }

                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by URL or method...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _applySearch();
            },
          )
              : null,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) => _applySearch(),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 8,
        children: [
          if (_currentFilter!.methods != null && _currentFilter!.methods!.isNotEmpty)
            Chip(
              label: Text('Methods: ${_currentFilter!.methods!.length}'),
              onDeleted: () {
                setState(() {
                  _currentFilter = LogFilter(
                    statusCodes: _currentFilter!.statusCodes,
                    logTypes: _currentFilter!.logTypes,
                    startDate: _currentFilter!.startDate,
                    endDate: _currentFilter!.endDate,
                    searchQuery: _currentFilter!.searchQuery,
                  );
                });
                _applyFilter();
              },
            ),
          if (_currentFilter!.statusCodes != null && _currentFilter!.statusCodes!.isNotEmpty)
            Chip(
              label: Text('Status: ${_currentFilter!.statusCodes!.length}'),
              onDeleted: () {
                setState(() {
                  _currentFilter = LogFilter(
                    methods: _currentFilter!.methods,
                    logTypes: _currentFilter!.logTypes,
                    startDate: _currentFilter!.startDate,
                    endDate: _currentFilter!.endDate,
                    searchQuery: _currentFilter!.searchQuery,
                  );
                });
                _applyFilter();
              },
            ),
          if (_currentFilter!.logTypes != null && _currentFilter!.logTypes!.isNotEmpty)
            Chip(
              label: Text('Types: ${_currentFilter!.logTypes!.length}'),
              onDeleted: () {
                setState(() {
                  _currentFilter = LogFilter(
                    methods: _currentFilter!.methods,
                    statusCodes: _currentFilter!.statusCodes,
                    startDate: _currentFilter!.startDate,
                    endDate: _currentFilter!.endDate,
                    searchQuery: _currentFilter!.searchQuery,
                  );
                });
                _applyFilter();
              },
            ),
          ActionChip(
            label: const Text('Clear All Filters'),
            onPressed: () {
              setState(() {
                _currentFilter = null;
              });
              context.read<LogBloc>().add(LoadLogsEvent());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.list_alt,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No logs found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Logs will appear when requests are intercepted',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(List<RequestLog> logs) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _buildLogCard(log);
      },
    );
  }

  Widget _buildLogCard(RequestLog log) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');
    final statusColor = _getStatusColor(log.statusCode);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Text(
            log.statusCode.toString(),
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          log.url,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            _buildChip(log.method.name, Colors.blue),
            const SizedBox(width: 8),
            _buildChip(
              log.logType == LogType.mock ? 'Mock' : 'Pass-through',
              log.logType == LogType.mock ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            _buildChip('${log.responseTimeMs}ms', Colors.purple),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'create_endpoint') {
              _createEndpointFromLog(log);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'create_endpoint',
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 20),
                  SizedBox(width: 8),
                  Text('Create Endpoint'),
                ],
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Timestamp', dateFormat.format(log.timestamp)),
                const Divider(),
                _buildDetailRow('Method', log.method.name),
                _buildDetailRow('URL', log.url),
                _buildDetailRow('Status Code', log.statusCode.toString()),
                _buildDetailRow('Response Time', '${log.responseTimeMs}ms'),
                _buildDetailRow('Type', log.logType == LogType.mock ? 'Mock' : 'Pass-through'),
                if (log.headers.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'Headers:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...log.headers.entries.map(
                        (entry) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 4),
                      child: Text('${entry.key}: ${entry.value}'),
                    ),
                  ),
                ],
                if (log.requestBody != null) ...[
                  const Divider(),
                  const Text(
                    'Request Body:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  JsonViewerWidget(
                    jsonString: log.requestBody!,
                    initialExpandDepth: 1,
                  ),
                ],
                if (log.responseBody != null) ...[
                  const Divider(),
                  const Text(
                    'Response Body:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  JsonViewerWidget(
                    jsonString: log.responseBody!,
                    initialExpandDepth: 1,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(value),
          ),
        ],
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

  Color _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return Colors.green;
    } else if (statusCode >= 300 && statusCode < 400) {
      return Colors.blue;
    } else if (statusCode >= 400 && statusCode < 500) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  void _applySearch() {
    final query = _searchController.text;
    final filter = LogFilter(
      methods: _currentFilter?.methods,
      statusCodes: _currentFilter?.statusCodes,
      logTypes: _currentFilter?.logTypes,
      startDate: _currentFilter?.startDate,
      endDate: _currentFilter?.endDate,
      searchQuery: query.isNotEmpty ? query : null,
    );
    setState(() {
      _currentFilter = filter;
    });
    context.read<LogBloc>().add(ApplyFilterEvent(filter));
  }

  void _applyFilter() {
    if (_currentFilter != null) {
      context.read<LogBloc>().add(ApplyFilterEvent(_currentFilter!));
    }
  }

  Future<void> _showFilterDialog() async {
    final result = await Navigator.push<LogFilter>(
      context,
      MaterialPageRoute(
        builder: (context) => LogFilterScreen(currentFilter: _currentFilter),
      ),
    );

    if (result != null) {
      setState(() {
        _currentFilter = result;
      });
      context.read<LogBloc>().add(ApplyFilterEvent(result));
    }
  }

  void _showClearDialog(bool filteredOnly) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(filteredOnly ? 'Clear Filtered Logs' : 'Clear All Logs'),
          content: Text(
            filteredOnly
                ? 'Are you sure you want to clear all filtered logs?'
                : 'Are you sure you want to clear all logs?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (filteredOnly && _currentFilter != null) {
                  context.read<LogBloc>().add(ClearFilteredLogsEvent(_currentFilter!));
                } else {
                  context.read<LogBloc>().add(ClearLogsEvent());
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportLogs() async {
    context.read<LogBloc>().add(ExportLogsEvent(filter: _currentFilter));
  }

  Future<void> _saveAndShareExport(String jsonData) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/logs_export.json');
      await file.writeAsString(jsonData);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Network Interceptor Logs Export',
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

  void _createEndpointFromLog(RequestLog log) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Create Endpoint from Log'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will create a new mock endpoint with the following details:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Method:', log.method.name.toUpperCase()),
                _buildInfoRow('URL Pattern:', '/${log.url}'),
                _buildInfoRow('Status Code:', log.statusCode.toString()),
                const SizedBox(height: 16),
                const Text(
                  'Mock Response:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log.responseBody ?? '{}',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 10,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _navigateToCreateEndpoint(log);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _navigateToCreateEndpoint(RequestLog log) async {
    // Extract URL path without query parameters
    String pattern = log.url;
    if (pattern.contains('?')) {
      pattern = pattern.split('?').first;
    }

    // Remove leading slash if exists
    if (pattern.startsWith('/')) {
      pattern = pattern.substring(1);
    }

    final now = DateTime.now();
    final newEndpoint = Endpoint(
      id: now.millisecondsSinceEpoch.toString(),
      pattern: pattern,
      matchType: MatchType.exact,
      mode: EndpointMode.mock,
      mockResponse: log.responseBody ?? '{}',
      delayMs: 0,
      targetUrl: null,
      createdAt: now,
      updatedAt: now,
      isEnabled: true,
      conditionalMocks: [],
      useConditionalMock: false,
      statusCode: log.statusCode,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EndpointFormScreen(endpoint: newEndpoint),
      ),
    );

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Endpoint created! You can modify it as needed.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
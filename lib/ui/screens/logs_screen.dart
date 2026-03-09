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
  RequestLog? _selectedLog;
  bool _isHeaderExpanded = true;

  @override
  void initState() {
    super.initState();
    context.read<LogBloc>().add(WatchLogsStarted());
  }

  @override
  void dispose() {
    _searchController.dispose();
    context.read<LogBloc>().add(WatchLogsStopped());
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
            icon: const Icon(Icons.share),
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
          _buildCollapsibleHeader(),
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
                  return _buildResponsiveLayout(state.logs);
                }

                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleHeader() {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isHeaderExpanded = !_isHeaderExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _isHeaderExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Search & Filters',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  if (_currentFilter != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 1),
                _buildSearchBar(),
                if (_currentFilter != null) _buildFilterChips(),
              ],
            ),
            crossFadeState: _isHeaderExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveLayout(List<RequestLog> logs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use master-detail layout for large screens (width > 800)
        if (constraints.maxWidth > 800) {
          return Row(
            children: [
              // Master: List of APIs
              SizedBox(
                width: 400,
                child: _buildLogList(logs, isMasterDetail: true),
              ),
              const VerticalDivider(width: 1),
              // Detail: Selected log details
              Expanded(
                child: _selectedLog == null
                    ? _buildSelectPrompt()
                    : Align(
                        alignment: AlignmentGeometry.topLeft,
                        child: _buildLogDetail(_selectedLog!)),
              ),
            ],
          );
        } else {
          // Single column layout for smaller screens
          return _buildLogList(logs, isMasterDetail: false);
        }
      },
    );
  }

  Widget _buildSelectPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.touch_app,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Select a log to view details',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogDetail(RequestLog log) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  log.url,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectedLog = null;
                  });
                },
                tooltip: 'Close',
              ),
              PopupMenuButton<String>(
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
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildChip(log.method.name, Colors.blue),
              const SizedBox(width: 8),
              _buildChip(
                log.logType == LogType.mock ? 'Mock' : 'Pass-through',
                log.logType == LogType.mock ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              _buildChip('${log.responseTimeMs}ms', Colors.purple),
              const SizedBox(width: 8),
              _buildChip(
                log.statusCode.toString(),
                _getStatusColor(log.statusCode),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Basic Info Section - Always visible
          _buildDetailRow('Timestamp', dateFormat.format(log.timestamp)),
          const Divider(),
          _buildDetailRow('Method', log.method.name),
          _buildDetailRow('URL', log.url),
          _buildDetailRow('Status Code', log.statusCode.toString()),
          _buildDetailRow('Response Time', '${log.responseTimeMs}ms'),
          _buildDetailRow(
              'Type', log.logType == LogType.mock ? 'Mock' : 'Pass-through'),

          // Headers Section - Collapsible
          if (log.headers.isNotEmpty) ...[
            const Divider(),
            _buildCollapsibleSection(
              title: 'Headers',
              icon: Icons.list_alt,
              child: Column(
                key: ValueKey(log.url),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: log.headers.entries
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Text('${entry.key}: ${entry.value}'),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          // Request Body Section - Collapsible
          if (log.requestBody != null) ...[
            const Divider(),
            _buildCollapsibleSection(
              title: 'Request Body',
              icon: Icons.upload,
              child: SizedBox(
                width: double.maxFinite,
                child: JsonViewerWidget(
                  key: ValueKey(log.url),
                  jsonString: log.requestBody!,
                  initialExpandDepth: 1,
                ),
              ),
            ),
          ],

          // Response Body Section - Collapsible
          if (log.responseBody != null) ...[
            const Divider(),
            _buildCollapsibleSection(
              title: 'Response Body',
              icon: Icons.download,
              child: SizedBox(
                width: double.maxFinite,
                child: JsonViewerWidget(
                  key: ValueKey(log.url),
                  jsonString: log.responseBody!,
                  initialExpandDepth: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return ExpansionTile(
      leading: Icon(icon, size: 20),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      initiallyExpanded: false,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: child,
        ),
      ],
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
          if (_currentFilter!.methods != null &&
              _currentFilter!.methods!.isNotEmpty)
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
          if (_currentFilter!.statusCodes != null &&
              _currentFilter!.statusCodes!.isNotEmpty)
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
          if (_currentFilter!.logTypes != null &&
              _currentFilter!.logTypes!.isNotEmpty)
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
              context.read<LogBloc>().add(WatchLogsStarted());
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

  Widget _buildLogList(List<RequestLog> logs, {required bool isMasterDetail}) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _buildLogCard(log, isMasterDetail: isMasterDetail);
      },
    );
  }

  Widget _buildLogCard(RequestLog log, {required bool isMasterDetail}) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');
    final statusColor = _getStatusColor(log.statusCode);
    final isSelected = isMasterDetail && _selectedLog?.id == log.id;

    if (isMasterDetail) {
      // Compact card for master-detail layout
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        color: isSelected ? Theme.of(context).highlightColor : null,
        child: ListTile(
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildChip(log.method.name, Colors.blue),
                  const SizedBox(width: 8),
                  _buildChip('${log.responseTimeMs}ms', Colors.purple),
                ],
              ),
            ],
          ),
          onTap: () {
            setState(() {
              _selectedLog = log;
            });
          },
        ),
      );
    } else {
      // Expandable card for single column layout
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
                  _buildDetailRow(
                      'Timestamp', dateFormat.format(log.timestamp)),
                  const Divider(),
                  _buildDetailRow('Method', log.method.name),
                  _buildDetailRow('URL', log.url),
                  _buildDetailRow('Status Code', log.statusCode.toString()),
                  _buildDetailRow('Response Time', '${log.responseTimeMs}ms'),
                  _buildDetailRow('Type',
                      log.logType == LogType.mock ? 'Mock' : 'Pass-through'),
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
    context.read<LogBloc>().add(WatchLogsStarted(filter: filter));
  }

  void _applyFilter() {
    if (_currentFilter != null) {
      context.read<LogBloc>().add(WatchLogsStarted(filter: _currentFilter));
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
      context.read<LogBloc>().add(WatchLogsStarted(filter: result));
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
                  context
                      .read<LogBloc>()
                      .add(ClearFilteredLogsEvent(_currentFilter!));
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
          SnackBar(
              content: Text('Export failed: $e'), backgroundColor: Colors.red),
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
                JsonViewerWidget(
                  jsonString: log.responseBody ?? '{}',
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

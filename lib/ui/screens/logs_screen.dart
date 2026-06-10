import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/endpoint.dart';
import '../../domain/entities/profile.dart';
import '../../domain/entities/request_log.dart';
import '../../domain/repositories/log_repository.dart';
import '../bloc/endpoint/endpoint_bloc.dart';
import '../bloc/log/log_bloc.dart';
import '../bloc/profile/profile_bloc.dart';
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
  String? _selectedProfileId;

  // Selection mode
  bool _isSelectionMode = false;
  final Set<String> _selectedLogIds = {};

  @override
  void initState() {
    super.initState();
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      _selectedProfileId = profileState.activeProfileId;
    }
    _startWatching();
  }

  @override
  void dispose() {
    _searchController.dispose();
    context.read<LogBloc>().add(StopWatchingLogsEvent());
    super.dispose();
  }

  void _startWatching() {
    final filter = (_currentFilter ?? const LogFilter()).copyWith(profileId: _selectedProfileId);
    context.read<LogBloc>().add(StartWatchingLogsEvent(filter: filter));
  }

  void _loadLogsWithProfile() {
    final filter = (_currentFilter ?? const LogFilter()).copyWith(profileId: _selectedProfileId);
    context.read<LogBloc>().add(StartWatchingLogsEvent(filter: filter));
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedLogIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<EndpointBloc, EndpointState>(
      listener: (context, endpointState) {
        if (endpointState is BatchCreateSuccessState) {
          _exitSelectionMode();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${endpointState.count} endpoints created in profile'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (endpointState is EndpointError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(endpointState.message), backgroundColor: Colors.red),
          );
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
        body: Column(
          children: [
            if (!_isSelectionMode) _buildCollapsibleHeader(),
            Expanded(
              child: BlocConsumer<LogBloc, LogState>(
                listener: (context, state) {
                  if (state is LogError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(state.message), backgroundColor: Colors.red),
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
                    if (state.logs.isEmpty) return _buildEmptyState();
                    return _buildResponsiveLayout(state.logs);
                  }
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
        floatingActionButton: _isSelectionMode && _selectedLogIds.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _showBatchCreateDialog,
                icon: const Icon(Icons.add_circle_outline),
                label: Text('Create ${_selectedLogIds.length} Endpoint${_selectedLogIds.length == 1 ? '' : 's'}'),
              )
            : null,
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      title: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, profileState) {
          if (profileState is ProfileLoaded && _selectedProfileId != null) {
            final profile = profileState.profiles.firstWhere(
              (p) => p.id == _selectedProfileId,
              orElse: () => profileState.profiles.first,
            );
            return Text('Logs · ${profile.name}');
          }
          return const Text('Request Logs');
        },
      ),
      actions: [
        BlocBuilder<LogBloc, LogState>(
          builder: (context, state) {
            final isStreaming = state is LogLoaded && state.isStreaming;
            return IconButton(
              icon: Icon(isStreaming ? Icons.pause_circle_outline : Icons.play_circle_outline),
              tooltip: isStreaming ? 'Stop live updates' : 'Start live updates',
              onPressed: () {
                if (isStreaming) {
                  context.read<LogBloc>().add(StopWatchingLogsEvent());
                } else {
                  _startWatching();
                }
              },
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.switch_account_outlined),
          onPressed: _showProfileSelector,
          tooltip: 'Switch Profile',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadLogsWithProfile,
          tooltip: 'Reload Logs',
        ),
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
            const PopupMenuItem(value: 'clear_all', child: Text('Clear All Logs')),
            const PopupMenuItem(value: 'clear_filtered', child: Text('Clear Filtered Logs')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectionMode,
      ),
      title: Text('${_selectedLogIds.length} selected'),
      actions: [
        BlocBuilder<LogBloc, LogState>(
          builder: (context, state) {
            final logs = state is LogLoaded ? state.logs : <RequestLog>[];
            final allSelected = logs.isNotEmpty && _selectedLogIds.length == logs.length;
            return TextButton(
              onPressed: () {
                setState(() {
                  if (allSelected) {
                    _selectedLogIds.clear();
                  } else {
                    _selectedLogIds.addAll(logs.map((l) => l.id));
                  }
                });
              },
              child: Text(allSelected ? 'Deselect All' : 'Select All',
                  style: const TextStyle(color: Colors.white)),
            );
          },
        ),
      ],
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
            onTap: () => setState(() => _isHeaderExpanded = !_isHeaderExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(_isHeaderExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey[700]),
                  const SizedBox(width: 8),
                  Text('Search & Filters',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey[700])),
                  const Spacer(),
                  BlocBuilder<LogBloc, LogState>(
                    builder: (context, state) {
                      final isStreaming = state is LogLoaded && state.isStreaming;
                      if (!isStreaming) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 4),
                            const Text('Live',
                                style: TextStyle(fontSize: 11, color: Colors.green,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_currentFilter != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Active',
                          style: TextStyle(fontSize: 12, color: Colors.blue[700],
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
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
        if (constraints.maxWidth > 800) {
          return Row(
            children: [
              SizedBox(
                width: 400,
                child: _buildLogList(logs, isMasterDetail: true),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selectedLog == null
                    ? _buildSelectPrompt()
                    : Align(
                        alignment: AlignmentGeometry.topLeft,
                        child: _buildLogDetail(_selectedLog!)),
              ),
            ],
          );
        }
        return _buildLogList(logs, isMasterDetail: false);
      },
    );
  }

  Widget _buildSelectPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Select a log to view details',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
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
                child: Text(log.url,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedLog = null),
                tooltip: 'Close',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'create_endpoint') _createEndpointFromLog(log);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'create_endpoint',
                    child: Row(children: [
                      Icon(Icons.add_circle_outline, size: 20),
                      SizedBox(width: 8),
                      Text('Create Endpoint'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              _buildChip(log.method.name, Colors.blue),
              _buildChip(log.logType == LogType.mock ? 'Mock' : 'Pass-through',
                  log.logType == LogType.mock ? Colors.green : Colors.orange),
              _buildChip('${log.responseTimeMs}ms', Colors.purple),
              _buildChip(log.statusCode.toString(), _getStatusColor(log.statusCode)),
            ],
          ),
          const SizedBox(height: 24),
          _buildDetailRow('Timestamp', dateFormat.format(log.timestamp)),
          const Divider(),
          _buildDetailRow('Method', log.method.name),
          _buildDetailRow('URL', log.url),
          _buildDetailRow('Status Code', log.statusCode.toString()),
          _buildDetailRow('Response Time', '${log.responseTimeMs}ms'),
          _buildDetailRow('Type', log.logType == LogType.mock ? 'Mock' : 'Pass-through'),
          if (log.headers.isNotEmpty) ...[
            const Divider(),
            _buildCollapsibleSection(
              title: 'Headers', icon: Icons.list_alt,
              child: Column(
                key: ValueKey(log.url),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: log.headers.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 4),
                          child: Text('${e.key}: ${e.value}'),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (log.requestBody != null) ...[
            const Divider(),
            _buildCollapsibleSection(
              title: 'Request Body', icon: Icons.upload,
              child: SizedBox(
                width: double.maxFinite,
                child: JsonViewerWidget(
                    key: ValueKey(log.url),
                    jsonString: log.requestBody!,
                    initialExpandDepth: 1),
              ),
            ),
          ],
          if (log.responseBody != null) ...[
            const Divider(),
            _buildCollapsibleSection(
              title: 'Response Body', icon: Icons.download,
              child: SizedBox(
                width: double.maxFinite,
                child: JsonViewerWidget(
                    key: ValueKey(log.url),
                    jsonString: log.responseBody!,
                    initialExpandDepth: 1),
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
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      initiallyExpanded: false,
      children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: child),
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
          if (_currentFilter!.methods != null && _currentFilter!.methods!.isNotEmpty)
            Chip(
              label: Text('Methods: ${_currentFilter!.methods!.length}'),
              onDeleted: () {
                setState(() => _currentFilter = LogFilter(
                  statusCodes: _currentFilter!.statusCodes,
                  logTypes: _currentFilter!.logTypes,
                  startDate: _currentFilter!.startDate,
                  endDate: _currentFilter!.endDate,
                  searchQuery: _currentFilter!.searchQuery,
                ));
                _applyFilter();
              },
            ),
          if (_currentFilter!.statusCodes != null && _currentFilter!.statusCodes!.isNotEmpty)
            Chip(
              label: Text('Status: ${_currentFilter!.statusCodes!.length}'),
              onDeleted: () {
                setState(() => _currentFilter = LogFilter(
                  methods: _currentFilter!.methods,
                  logTypes: _currentFilter!.logTypes,
                  startDate: _currentFilter!.startDate,
                  endDate: _currentFilter!.endDate,
                  searchQuery: _currentFilter!.searchQuery,
                ));
                _applyFilter();
              },
            ),
          if (_currentFilter!.logTypes != null && _currentFilter!.logTypes!.isNotEmpty)
            Chip(
              label: Text('Types: ${_currentFilter!.logTypes!.length}'),
              onDeleted: () {
                setState(() => _currentFilter = LogFilter(
                  methods: _currentFilter!.methods,
                  statusCodes: _currentFilter!.statusCodes,
                  startDate: _currentFilter!.startDate,
                  endDate: _currentFilter!.endDate,
                  searchQuery: _currentFilter!.searchQuery,
                ));
                _applyFilter();
              },
            ),
          ActionChip(
            label: const Text('Clear All Filters'),
            onPressed: () {
              setState(() => _currentFilter = null);
              _loadLogsWithProfile();
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
          Icon(Icons.list_alt, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No logs found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('Logs will appear when requests are intercepted',
              style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildLogList(List<RequestLog> logs, {required bool isMasterDetail}) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) =>
          _buildLogCard(logs[index], isMasterDetail: isMasterDetail),
    );
  }

  Widget _buildLogCard(RequestLog log, {required bool isMasterDetail}) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm:ss');
    final statusColor = _getStatusColor(log.statusCode);
    final isSelected = _isSelectionMode && _selectedLogIds.contains(log.id);
    final isMasterSelected = isMasterDetail && _selectedLog?.id == log.id;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : (isMasterSelected ? Theme.of(context).highlightColor : null),
      child: isMasterDetail
          ? ListTile(
              leading: _isSelectionMode
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(log.id),
                    )
                  : CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.2),
                      child: Text(log.statusCode.toString(),
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
              title: Text(log.url,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  _buildChip(log.method.name, Colors.blue),
                  const SizedBox(width: 8),
                  _buildChip('${log.responseTimeMs}ms', Colors.purple),
                ]),
              ),
              onTap: () => _isSelectionMode
                  ? _toggleSelection(log.id)
                  : setState(() => _selectedLog = log),
              onLongPress: () => _enterSelectionMode(log.id),
            )
          : ExpansionTile(
              leading: _isSelectionMode
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(log.id),
                    )
                  : CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.2),
                      child: Text(log.statusCode.toString(),
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
              title: Text(log.url,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Wrap(
                spacing: 4,
                children: [
                  _buildChip(log.method.name, Colors.blue),
                  _buildChip(
                      log.logType == LogType.mock ? 'Mock' : 'Pass-through',
                      log.logType == LogType.mock ? Colors.green : Colors.orange),
                  _buildChip('${log.responseTimeMs}ms', Colors.purple),
                ],
              ),
              trailing: _isSelectionMode
                  ? null
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'create_endpoint') _createEndpointFromLog(log);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'create_endpoint',
                          child: Row(children: [
                            Icon(Icons.add_circle_outline, size: 20),
                            SizedBox(width: 8),
                            Text('Create Endpoint'),
                          ]),
                        ),
                      ],
                    ),
              onExpansionChanged: (_isSelectionMode)
                  ? (_) => _toggleSelection(log.id)
                  : null,
              children: _isSelectionMode
                  ? []
                  : [
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
                            _buildDetailRow('Type',
                                log.logType == LogType.mock ? 'Mock' : 'Pass-through'),
                            if (log.headers.isNotEmpty) ...[
                              const Divider(),
                              const Text('Headers:',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...log.headers.entries.map((e) => Padding(
                                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                                    child: Text('${e.key}: ${e.value}'),
                                  )),
                            ],
                            if (log.requestBody != null) ...[
                              const Divider(),
                              const Text('Request Body:',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              JsonViewerWidget(
                                  jsonString: log.requestBody!, initialExpandDepth: 1),
                            ],
                            if (log.responseBody != null) ...[
                              const Divider(),
                              const Text('Response Body:',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              JsonViewerWidget(
                                  jsonString: log.responseBody!, initialExpandDepth: 1),
                            ],
                          ],
                        ),
                      ),
                    ],
            ),
    );
  }

  void _enterSelectionMode(String logId) {
    setState(() {
      _isSelectionMode = true;
      _selectedLogIds.add(logId);
    });
  }

  void _toggleSelection(String logId) {
    setState(() {
      if (_selectedLogIds.contains(logId)) {
        _selectedLogIds.remove(logId);
        if (_selectedLogIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedLogIds.add(logId);
      }
    });
  }

  void _showBatchCreateDialog() {
    final state = context.read<LogBloc>().state;
    if (state is! LogLoaded) return;
    final selectedLogs = state.logs.where((l) => _selectedLogIds.contains(l.id)).toList();

    showDialog(
      context: context,
      builder: (ctx) => _BatchCreateDialog(
        selectedCount: selectedLogs.length,
        onConfirm: (profileId, delayMs) {
          Navigator.pop(ctx);
          context.read<EndpointBloc>().add(BatchCreateEndpointsFromLogsEvent(
            logs: selectedLogs,
            profileId: profileId,
            delayMs: delayMs,
          ));
        },
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
            child: Text('$label:',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Color _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 300 && statusCode < 400) return Colors.blue;
    if (statusCode >= 400 && statusCode < 500) return Colors.orange;
    return Colors.red;
  }

  void _applySearch() {
    final query = _searchController.text;
    final filter = (_currentFilter ?? const LogFilter()).copyWith(
      searchQuery: query.isNotEmpty ? query : null,
      profileId: _selectedProfileId,
    );
    setState(() => _currentFilter = filter);
    context.read<LogBloc>().add(ApplyFilterEvent(filter));
  }

  void _applyFilter() {
    final effective =
        (_currentFilter ?? const LogFilter()).copyWith(profileId: _selectedProfileId);
    context.read<LogBloc>().add(ApplyFilterEvent(effective));
  }

  Future<void> _showFilterDialog() async {
    final logBloc = context.read<LogBloc>();
    final result = await Navigator.push<LogFilter>(
      context,
      MaterialPageRoute(
          builder: (context) => LogFilterScreen(currentFilter: _currentFilter)),
    );
    if (result != null) {
      setState(() => _currentFilter = result);
      final effective = result.copyWith(profileId: _selectedProfileId);
      logBloc.add(ApplyFilterEvent(effective));
    }
  }

  void _showProfileSelector() {
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is! ProfileLoaded) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Text('Filter by Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.all_inclusive,
                  color: _selectedProfileId == null
                      ? Theme.of(context).colorScheme.primary
                      : null),
              title: const Text('All Profiles'),
              trailing: _selectedProfileId == null
                  ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _selectedProfileId = null);
                _loadLogsWithProfile();
              },
            ),
            ...profileState.profiles.map((profile) => ListTile(
                  leading: Icon(Icons.folder_outlined,
                      color: profile.id == _selectedProfileId
                          ? Theme.of(context).colorScheme.primary
                          : null),
                  title: Text(profile.name),
                  trailing: profile.id == _selectedProfileId
                      ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _selectedProfileId = profile.id);
                    _loadLogsWithProfile();
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showClearDialog(bool filteredOnly) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(filteredOnly ? 'Clear Filtered Logs' : 'Clear All Logs'),
        content: Text(filteredOnly
            ? 'Are you sure you want to clear all filtered logs?'
            : 'Are you sure you want to clear all logs?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final effective = (_currentFilter ?? const LogFilter())
                  .copyWith(profileId: _selectedProfileId);
              if (filteredOnly) {
                context.read<LogBloc>().add(ClearFilteredLogsEvent(effective));
              } else {
                context.read<LogBloc>().add(ClearLogsEvent());
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Network Interceptor Logs Export');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export successful')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _createEndpointFromLog(RequestLog log) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Create Endpoint from Log'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This will create a new mock endpoint with the following details:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildInfoRow('Method:', log.method.name.toUpperCase()),
              _buildInfoRow('URL Pattern:', '/${log.url}'),
              _buildInfoRow('Status Code:', log.statusCode.toString()),
              const SizedBox(height: 16),
              const Text('Mock Response:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              JsonViewerWidget(jsonString: log.responseBody ?? '{}'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _navigateToCreateEndpoint(log);
            },
            child: const Text('Create'),
          ),
        ],
      ),
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
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _navigateToCreateEndpoint(RequestLog log) async {
    String pattern = log.url;
    if (pattern.contains('?')) pattern = pattern.split('?').first;
    if (pattern.startsWith('/')) pattern = pattern.substring(1);

    final now = DateTime.now();
    final profileId =
        log.profileId.isNotEmpty ? log.profileId : (_selectedProfileId ?? 'default');
    final newEndpoint = Endpoint(
      id: now.millisecondsSinceEpoch.toString(),
      profileId: profileId,
      pattern: pattern,
      matchType: MatchType.exact,
      mode: EndpointMode.mock,
      mockResponse: log.responseBody ?? '{}',
      delayMs: 0,
      targetUrl: null,
      createdAt: now,
      updatedAt: now,
      isEnabled: true,
      conditionalMocks: const [],
      useConditionalMock: false,
      statusCode: log.statusCode,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EndpointFormScreen(endpoint: newEndpoint, profileId: profileId),
      ),
    );

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

// ── Batch Create Dialog ──────────────────────────────────────────────────────

class _BatchCreateDialog extends StatefulWidget {
  final int selectedCount;
  final void Function(String profileId, int delayMs) onConfirm;

  const _BatchCreateDialog({required this.selectedCount, required this.onConfirm});

  @override
  State<_BatchCreateDialog> createState() => _BatchCreateDialogState();
}

class _BatchCreateDialogState extends State<_BatchCreateDialog> {
  String? _selectedProfileId;
  final _delayController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      _selectedProfileId = profileState.activeProfileId;
    }
  }

  @override
  void dispose() {
    _delayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        final profiles = profileState is ProfileLoaded ? profileState.profiles : <Profile>[];

        return AlertDialog(
          title: Text('Create ${widget.selectedCount} Endpoint${widget.selectedCount == 1 ? '' : 's'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Target Profile',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedProfileId,
                  items: profiles
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedProfileId = val),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create new profile'),
                  onPressed: () => _showCreateProfileDialog(context),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _delayController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Default delay (ms)',
                    border: OutlineInputBorder(),
                    helperText: 'Applied to all created endpoints',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: _selectedProfileId == null
                  ? null
                  : () {
                      final delay = int.tryParse(_delayController.text) ?? 0;
                      widget.onConfirm(_selectedProfileId!, delay);
                    },
              child: Text('Create ${widget.selectedCount} Endpoint${widget.selectedCount == 1 ? '' : 's'}'),
            ),
          ],
        );
      },
    );
  }

  void _showCreateProfileDialog(BuildContext parentContext) {
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
                parentContext.read<ProfileBloc>().add(CreateProfileEvent(name: name));
                Navigator.pop(ctx);
                // After creation, ProfileBloc will emit ProfileLoaded with new profile
                // The dropdown will update automatically via BlocBuilder
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

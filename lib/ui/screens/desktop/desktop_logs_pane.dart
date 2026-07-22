import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/entities/request_log.dart';
import '../../../domain/repositories/log_repository.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';
import '../../bloc/log/log_bloc.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../dialog/new_collection_dialog.dart';
import 'desktop_log_filter_dialog.dart';

/// Middle pane of the wide-layout workspace: the activity/logs feed for the
/// selected server, with multi-select → "New collection" / "Add to
/// collection", mirroring `LogsScreen`'s selection flow in a narrower pane.
class DesktopLogsPane extends StatefulWidget {
  final String profileId;
  final String? selectedLogId;
  final ValueChanged<RequestLog?> onLogSelected;

  const DesktopLogsPane({
    super.key,
    required this.profileId,
    required this.selectedLogId,
    required this.onLogSelected,
  });

  @override
  State<DesktopLogsPane> createState() => _DesktopLogsPaneState();
}

class _DesktopLogsPaneState extends State<DesktopLogsPane> {
  LogFilter? _currentFilter;
  final Set<String> _selectedLogIds = {};

  @override
  void initState() {
    super.initState();
    _startWatching();
  }

  @override
  void didUpdateWidget(DesktopLogsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      setState(() {
        _currentFilter = null;
        _selectedLogIds.clear();
      });
      _startWatching();
    }
  }

  @override
  void dispose() {
    context.read<LogBloc>().add(StopWatchingLogsEvent());
    super.dispose();
  }

  void _startWatching() {
    final filter = (_currentFilter ?? const LogFilter()).copyWith(profileId: widget.profileId);
    context.read<LogBloc>().add(StartWatchingLogsEvent(filter: filter));
  }

  bool get _filterActive {
    final f = _currentFilter;
    if (f == null) return false;
    return (f.methods?.isNotEmpty ?? false) ||
        (f.statusCodes?.isNotEmpty ?? false) ||
        (f.logTypes?.isNotEmpty ?? false) ||
        f.ip != null ||
        f.startDate != null ||
        f.endDate != null;
  }

  List<RequestLog> _selectedLogs(List<RequestLog> logs) =>
      logs.where((l) => _selectedLogIds.contains(l.id)).toList();

  /// Shelf's `Request.url` has no leading slash and is empty for the root
  /// path, so a bare `GET /` would otherwise render as blank.
  String _displayPath(String url) => url.isEmpty ? '/' : (url.startsWith('/') ? url : '/$url');

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return BlocBuilder<LogBloc, LogState>(
      builder: (context, state) {
        final logs = state is LogLoaded ? state.logs : <RequestLog>[];
        // Loading (e.g. right after this pane mounts) is transient — don't
        // flash the empty state over whatever was showing a moment ago.
        final loading = state is LogLoading;
        return Container(
          color: t.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(context, t, logs),
              if (_selectedLogIds.isNotEmpty) _buildSelectionBar(context, t, logs),
              Expanded(
                child: logs.isEmpty
                    ? (loading
                        ? const SizedBox.shrink()
                        : Center(
                            child: Text('No requests yet',
                                style: t.sans(color: t.textMuted))))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: logs.length,
                        itemBuilder: (context, i) => _buildLogRow(t, logs[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context, ArbTokens t, List<RequestLog> logs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: Text('${logs.length} request${logs.length == 1 ? '' : 's'}',
                style: t.sans(size: 13, weight: FontWeight.w600, color: t.textSecondary)),
          ),
          IconButton(
            tooltip: 'Clear logs',
            icon: Icon(Icons.delete_sweep_outlined, size: 20, color: t.textSecondary),
            onPressed: logs.isEmpty ? null : () => _confirmClearLogs(),
          ),
          IconButton(
            tooltip: 'Filter',
            icon: Icon(Icons.filter_list, size: 20,
                color: _filterActive ? t.accent : t.textSecondary),
            onPressed: () => _showFilterDialog(logs),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context, ArbTokens t, List<RequestLog> logs) {
    return Container(
      color: t.accentSoft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text('${_selectedLogIds.length} selected',
              style: t.sans(size: 12.5, weight: FontWeight.w700, color: t.accent)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(_selectedLogIds.clear),
            child: Text('Clear', style: t.sans(size: 12, color: t.textSecondary)),
          ),
          IconButton(
            tooltip: 'New collection',
            icon: Icon(Icons.create_new_folder_outlined, size: 20, color: t.accent),
            onPressed: () => _createCollectionFromSelection(logs),
          ),
          BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, profileState) {
              final profiles =
                  profileState is ProfileLoaded ? profileState.profiles : <Profile>[];
              return PopupMenuButton<String>(
                tooltip: 'Add to collection',
                icon: Icon(Icons.playlist_add, size: 20, color: t.textSecondary),
                onSelected: (profileId) => _addSelectionToProfile(logs, profileId),
                itemBuilder: (context) => profiles
                    .map((p) => PopupMenuItem(value: p.id, child: Text(p.name)))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogRow(ArbTokens t, RequestLog log) {
    final selected = _selectedLogIds.contains(log.id);
    final isCurrent = log.id == widget.selectedLogId;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent ? t.accentSoft : t.surface,
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(color: isCurrent ? t.accent : t.border),
      ),
      child: Row(
        children: [
          if (isCurrent)
            Container(
              width: 3,
              height: 40,
              margin: const EdgeInsets.only(left: 2),
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Expanded(
            child: ListTile(
              dense: true,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
              leading: Checkbox(
                value: selected,
                activeColor: t.accent,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedLogIds.add(log.id);
                  } else {
                    _selectedLogIds.remove(log.id);
                  }
                }),
              ),
              title: Row(
                children: [
                  _methodChip(t, log.method.name.toUpperCase()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_displayPath(log.url),
                        overflow: TextOverflow.ellipsis, style: t.mono(size: 12.5)),
                  ),
                  _statusChip(t, log.statusCode),
                ],
              ),
              subtitle: Text(
                '${log.logType == LogType.mock ? 'mock' : 'pass-through'} · ${log.responseTimeMs}ms'
                '${log.ip != null ? ' · ${log.ip}' : ''}',
                style: t.mono(size: 10.5, color: t.textMuted),
              ),
              onTap: () => widget.onLogSelected(log),
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodChip(ArbTokens t, String method) {
    final color = t.methodColor(method);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(method, style: t.mono(size: 10, weight: FontWeight.w700, color: color)),
    );
  }

  Widget _statusChip(ArbTokens t, int code) {
    final color = t.statusColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$code', style: t.mono(size: 10, weight: FontWeight.w700, color: color)),
    );
  }

  void _confirmClearLogs() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear logs'),
        content: const Text('Delete all requests logged for this server? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<LogBloc>().add(
                    ClearFilteredLogsEvent(LogFilter(profileId: widget.profileId)),
                  );
              Navigator.pop(ctx);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilterDialog(List<RequestLog> logs) async {
    final availableIps = (logs.map((l) => l.ip).whereType<String>().toSet().toList()..sort());
    final result = await showDialog<LogFilter>(
      context: context,
      builder: (context) =>
          DesktopLogFilterDialog(currentFilter: _currentFilter, availableIps: availableIps),
    );
    if (result != null) {
      setState(() => _currentFilter = result);
      context
          .read<LogBloc>()
          .add(ApplyFilterEvent(result.copyWith(profileId: widget.profileId)));
    }
  }

  Future<void> _createCollectionFromSelection(List<RequestLog> logs) async {
    final selectedLogs = _selectedLogs(logs);
    if (selectedLogs.isEmpty) return;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => NewCollectionDialog(count: selectedLogs.length),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    final profileBloc = context.read<ProfileBloc>();
    final endpointBloc = context.read<EndpointBloc>();
    final priorIds = profileBloc.state is ProfileLoaded
        ? (profileBloc.state as ProfileLoaded).profiles.map((p) => p.id).toSet()
        : <String>{};

    late final StreamSubscription subscription;
    subscription = profileBloc.stream.listen((state) {
      if (state is ProfileLoaded) {
        final created = state.profiles.firstWhere(
          (p) => !priorIds.contains(p.id) && p.name == trimmed,
          orElse: () => state.profiles.last,
        );
        endpointBloc.add(BatchCreateEndpointsFromLogsEvent(
          logs: selectedLogs,
          profileId: created.id,
          delayMs: 0,
        ));
        subscription.cancel();
      }
    });
    profileBloc.add(CreateProfileEvent(name: trimmed));
    setState(_selectedLogIds.clear);
  }

  void _addSelectionToProfile(List<RequestLog> logs, String profileId) {
    final selectedLogs = _selectedLogs(logs);
    if (selectedLogs.isEmpty) return;
    context.read<EndpointBloc>().add(BatchCreateEndpointsFromLogsEvent(
          logs: selectedLogs,
          profileId: profileId,
          delayMs: 0,
        ));
    setState(_selectedLogIds.clear);
  }
}

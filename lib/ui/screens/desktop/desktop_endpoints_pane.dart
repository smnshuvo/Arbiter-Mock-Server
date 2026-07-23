import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/network_condition.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';

/// What to do with the JSON once [ExportEndpointsEvent] comes back — the
/// export round-trips through the bloc, so the intent has to be remembered.
enum _ExportAction { save, share }

/// Middle-pane alternative to [DesktopLogsPane]: browse, enable/disable, and
/// select endpoints directly from the workspace instead of only through the
/// Manage overlay. Carries its own import/export toolbar, and is reused as
/// the body of [MobileEndpointsScreen] on phones.
class DesktopEndpointsPane extends StatefulWidget {
  final String profileId;
  final String profileName;
  final String? selectedEndpointId;
  final ValueChanged<Endpoint> onEndpointSelected;
  final VoidCallback onAddEndpoint;

  /// Called instead of [onEndpointSelected] when the endpoint currently open
  /// in the editor is the one that just got deleted, so the caller can clear
  /// its selection rather than keep showing an editor for a gone endpoint.
  final VoidCallback? onSelectedEndpointDeleted;

  const DesktopEndpointsPane({
    super.key,
    required this.profileId,
    required this.profileName,
    required this.selectedEndpointId,
    required this.onEndpointSelected,
    required this.onAddEndpoint,
    this.onSelectedEndpointDeleted,
  });

  @override
  State<DesktopEndpointsPane> createState() => _DesktopEndpointsPaneState();
}

class _DesktopEndpointsPaneState extends State<DesktopEndpointsPane> {
  _ExportAction _pendingExportAction = _ExportAction.share;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return BlocConsumer<EndpointBloc, EndpointState>(
      listener: (context, state) {
        if (state is EndpointError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        } else if (state is EndpointExported) {
          switch (_pendingExportAction) {
            case _ExportAction.save:
              _saveExportToDevice(state.jsonData);
            case _ExportAction.share:
              _saveAndShareExport(state.jsonData);
          }
        }
      },
      builder: (context, state) {
        final endpoints = state is EndpointLoaded ? state.endpoints : <Endpoint>[];
        return Container(
          color: t.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(t, endpoints),
              Expanded(
                child: endpoints.isEmpty
                    ? Center(
                        child: Text('No endpoints yet', style: t.sans(color: t.textMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: endpoints.length,
                        itemBuilder: (context, i) => _buildRow(context, t, endpoints[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(ArbTokens t, List<Endpoint> endpoints) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: Text('${endpoints.length} endpoint${endpoints.length == 1 ? '' : 's'}',
                style: t.sans(size: 13, weight: FontWeight.w600, color: t.textSecondary)),
          ),
          IconButton(
            tooltip: 'Import',
            icon: Icon(Icons.downloading, size: 20, color: t.textSecondary),
            onPressed: _importEndpoints,
          ),
          PopupMenuButton<_ExportAction>(
            tooltip: 'Export',
            icon: Icon(Icons.ios_share, size: 20, color: t.textSecondary),
            color: t.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.radiusSm),
              side: BorderSide(color: t.border),
            ),
            onSelected: _exportEndpoints,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _ExportAction.save,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.save_alt, color: t.textSecondary),
                  title: Text('Save to device', style: t.sans(size: 13)),
                ),
              ),
              PopupMenuItem(
                value: _ExportAction.share,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share, color: t.textSecondary),
                  title: Text('Share…', style: t.sans(size: 13)),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Add endpoint',
            icon: Icon(Icons.add, size: 20, color: t.accent),
            onPressed: widget.onAddEndpoint,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, ArbTokens t, Endpoint ep) {
    final selected = ep.id == widget.selectedEndpointId;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected ? t.accentSoft : t.surface,
        borderRadius: BorderRadius.circular(t.radiusSm),
        border: Border.all(color: selected ? t.accent : t.border),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
        title: Row(
          children: [
            _methodChip(t, ep.method ?? 'ANY'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ep.pattern,
                  overflow: TextOverflow.ellipsis,
                  style: t.mono(size: 12.5, color: ep.isEnabled ? t.textPrimary : t.textMuted)),
            ),
          ],
        ),
        subtitle: Text(
          ep.mode == EndpointMode.mock ? 'Mock · ${ep.statusCode}' : 'Pass-through',
          style: t.sans(size: 10.5, weight: FontWeight.w500, color: t.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: ep.isEnabled,
              activeThumbColor: t.accent,
              onChanged: (v) => context
                  .read<EndpointBloc>()
                  .add(UpdateEndpointEvent(ep.copyWith(isEnabled: v))),
            ),
            IconButton(
              tooltip: 'Delete endpoint',
              icon: const Icon(Icons.delete_outline, size: 18),
              color: t.textMuted,
              onPressed: () => _confirmDelete(t, ep),
            ),
          ],
        ),
        onTap: () => widget.onEndpointSelected(ep),
      ),
    );
  }

  void _confirmDelete(ArbTokens t, Endpoint ep) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete endpoint'),
        content: Text('Are you sure you want to delete "${ep.pattern}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<EndpointBloc>().add(DeleteEndpointEvent(ep.id, widget.profileId));
              if (ep.id == widget.selectedEndpointId) {
                widget.onSelectedEndpointDeleted?.call();
              }
              Navigator.pop(dialogContext);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
        final endpoints = endpointsJson.map((json) => _jsonToEndpoint(json)).toList();

        if (mounted) {
          context.read<EndpointBloc>().add(ImportEndpointsEvent(endpoints, widget.profileId));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${endpoints.length} endpoints into current profile')),
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

  void _exportEndpoints(_ExportAction action) {
    _pendingExportAction = action;
    context.read<EndpointBloc>().add(ExportEndpointsEvent(widget.profileId));
  }

  /// Writes the export through the OS save dialog, so the user picks the
  /// destination (Downloads, Files, a SAF folder on Android…).
  Future<void> _saveExportToDevice(String jsonData) async {
    try {
      final safeName =
          widget.profileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final profileName = safeName.isEmpty ? 'arbiter' : safeName;
      final stamp = DateTime.now()
          .toIso8601String()
          .split('.')
          .first
          .replaceAll(RegExp(r'[:T]'), '-');
      // saveFile writes the bytes itself on both mobile and desktop.
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save endpoints',
        fileName: '${profileName}_endpoints_$stamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonData),
      );

      if (!mounted) return;
      if (path == null) return; // user cancelled

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $path')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
      id: json['id'] ?? const Uuid().v4(),
      profileId: widget.profileId,
      pattern: json['pattern'],
      method: json['method'],
      matchType: MatchType.values
          .firstWhere((e) => e.name == json['matchType'], orElse: () => MatchType.exact),
      mode: EndpointMode.values
          .firstWhere((e) => e.name == json['mode'], orElse: () => EndpointMode.mock),
      mockResponse: json['mockResponse'],
      statusCode: json['statusCode'] ?? 200,
      delayMs: json['delayMs'] ?? 0,
      targetUrl: json['targetUrl'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
      isEnabled: json['isEnabled'] == 1 || json['isEnabled'] == true,
      // Absent in exports made before network simulation existed → none.
      networkCondition: NetworkConditionX.fromName(json['networkCondition']),
    );
  }
}

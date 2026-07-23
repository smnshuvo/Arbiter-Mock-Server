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

/// Import/export controls for a profile's endpoints — lives in the Manage
/// sheet/dialog (moved out of the endpoints list's own toolbar so that
/// toolbar could shrink down to just a FAB for adding one).
class EndpointImportExportActions extends StatefulWidget {
  final String profileId;
  final String profileName;

  const EndpointImportExportActions({
    super.key,
    required this.profileId,
    required this.profileName,
  });

  @override
  State<EndpointImportExportActions> createState() =>
      _EndpointImportExportActionsState();
}

class _EndpointImportExportActionsState extends State<EndpointImportExportActions> {
  _ExportAction _pendingExportAction = _ExportAction.share;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return BlocListener<EndpointBloc, EndpointState>(
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
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _importEndpoints,
              style: OutlinedButton.styleFrom(
                foregroundColor: t.textSecondary,
                side: BorderSide(color: t.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
              ),
              icon: const Icon(Icons.downloading, size: 18),
              label: const Text('Import'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PopupMenuButton<_ExportAction>(
              tooltip: 'Export',
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
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(t.radiusSm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ios_share, size: 18, color: t.textSecondary),
                    const SizedBox(width: 8),
                    Text('Export',
                        style: t.sans(size: 13, weight: FontWeight.w600, color: t.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
      final safeName = widget.profileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
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

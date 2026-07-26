import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/endpoint.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';

/// Middle-pane alternative to [DesktopLogsPane]: browse, enable/disable, and
/// select endpoints directly from the workspace instead of only through the
/// Manage overlay. Import/export live in the Manage sheet/dialog instead of
/// here — this pane is just the list plus a FAB for adding one. Reused as
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
  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return BlocConsumer<EndpointBloc, EndpointState>(
      listener: (context, state) {
        if (state is EndpointError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      builder: (context, state) {
        // EndpointBloc is shared across servers, so its last EndpointLoaded can
        // still belong to the previously opened one while this pane's own
        // LoadEndpointsEvent is in flight. Render only what matches this pane,
        // otherwise the wrong server's endpoints flash up — and tapping one
        // during that window opens an endpoint from a different server.
        final endpoints = state is EndpointLoaded && state.profileId == widget.profileId
            ? state.endpoints
            : <Endpoint>[];
        return Container(
          color: t.canvas,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildToolbar(t, endpoints),
                  Expanded(
                    child: endpoints.isEmpty
                        ? Center(
                            child:
                                Text('No endpoints yet', style: t.sans(color: t.textMuted)))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                            itemCount: endpoints.length,
                            itemBuilder: (context, i) => _buildRow(context, t, endpoints[i]),
                          ),
                  ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton(
                  tooltip: 'Add endpoint',
                  backgroundColor: t.accent,
                  onPressed: widget.onAddEndpoint,
                  child: const Icon(Icons.add, color: Colors.white),
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
      child: Text('${endpoints.length} endpoint${endpoints.length == 1 ? '' : 's'}',
          style: t.sans(size: 13, weight: FontWeight.w600, color: t.textSecondary)),
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
}

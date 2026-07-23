import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/profile/profile_bloc.dart';

/// Left-hand rail of the wide-layout workspace: lists every [Profile], with
/// a running-state dot and endpoint count.
class ServerRail extends StatelessWidget {
  final String selectedProfileId;
  final Map<String, ({String url, int port})> runningMap;
  final Map<String, int> endpointCounts;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreateProfile;

  const ServerRail({
    super.key,
    required this.selectedProfileId,
    required this.runningMap,
    required this.endpointCounts,
    required this.onSelect,
    required this.onCreateProfile,
  });

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        final profiles = state is ProfileLoaded ? state.profiles : <Profile>[];
        return Container(
          color: t.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('SERVERS', style: t.label),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final p in profiles) _buildRow(context, t, p),
                  ],
                ),
              ),
              Divider(height: 1, color: t.border),
              ListTile(
                dense: true,
                leading: Icon(Icons.add, size: 20, color: t.accent),
                title: Text('New server', style: t.sans(size: 13, color: t.accent)),
                onTap: onCreateProfile,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, ArbTokens t, Profile p) {
    final running = runningMap.containsKey(p.id);
    final selected = p.id == selectedProfileId;
    final subtitle = running ? 'Running' : 'Not running';
    final epCount = endpointCounts[p.id];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected ? t.accentSoft : null,
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
        leading: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: running ? t.green : t.textMuted,
          ),
        ),
        title: Text(p.name,
            overflow: TextOverflow.ellipsis,
            style: t.sans(
                size: 13,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? t.accent : t.textPrimary)),
        subtitle: Text(subtitle,
            overflow: TextOverflow.ellipsis, style: t.mono(size: 10.5, color: t.textMuted)),
        trailing: epCount != null
            ? Text('$epCount', style: t.mono(size: 10.5, color: t.textMuted))
            : null,
        onTap: () => onSelect(p.id),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/server/server_bloc.dart';
import 'arb_bottom_sheet.dart';

/// Bottom sheet for switching which server's activity the mobile logs screen
/// is showing — the phone has no room for the desktop workspace's always-
/// visible server rail, so this stands in for it.
Future<String?> showProfileSwitchSheet({
  required BuildContext context,
  required String activeProfileId,
}) {
  return showArbBottomSheet<String>(
    context: context,
    title: 'Switch server',
    builder: (_) => _ProfileSwitchSheetBody(activeProfileId: activeProfileId),
  );
}

class _ProfileSwitchSheetBody extends StatelessWidget {
  final String activeProfileId;
  const _ProfileSwitchSheetBody({required this.activeProfileId});

  Set<String> _runningIds(ServerState state) {
    if (state is MultiServerRunning) {
      return state.runningServers.map((s) => s.profileId).toSet();
    }
    if (state is ServerRunning) return {state.profileId};
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final profiles = context.watch<ProfileBloc>().state is ProfileLoaded
        ? (context.watch<ProfileBloc>().state as ProfileLoaded).profiles
        : <Profile>[];
    final runningIds = _runningIds(context.watch<ServerBloc>().state);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      children: [
        for (final p in profiles)
          _row(context, t, p, running: runningIds.contains(p.id), selected: p.id == activeProfileId),
      ],
    );
  }

  Widget _row(BuildContext context, ArbTokens t, Profile p,
      {required bool running, required bool selected}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected ? t.accentSoft : null,
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      child: ListTile(
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
                size: 14,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? t.accent : t.textPrimary)),
        subtitle: Text(running ? 'Running' : 'Not running',
            style: t.mono(size: 11, color: t.textMuted)),
        onTap: () => Navigator.pop(context, p.id),
      ),
    );
  }
}

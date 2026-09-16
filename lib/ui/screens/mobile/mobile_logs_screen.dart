import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ads/ad_banner.dart';
import '../../../core/ads/ad_config.dart';
import '../../../domain/entities/profile.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../desktop/desktop_logs_pane.dart';
import 'mobile_detail_screen.dart';
import 'profile_switch_sheet.dart';

/// Full-screen mobile equivalent of the desktop workspace's logs pane. Since
/// there's no always-visible server rail on a phone, tapping the title opens
/// a bottom sheet to switch which server's activity is shown. Tapping a log
/// pushes [MobileDetailScreen] instead of swapping in a side pane.
class MobileLogsScreen extends StatefulWidget {
  /// Server whose logs to show. Null falls back to the active profile (the
  /// header's generic logs button); server cards pass their own id so they
  /// don't depend on the active-profile switch having landed yet.
  final String? profileId;

  const MobileLogsScreen({super.key, this.profileId});

  @override
  State<MobileLogsScreen> createState() => _MobileLogsScreenState();
}

class _MobileLogsScreenState extends State<MobileLogsScreen> {
  late String _profileId;

  @override
  void initState() {
    super.initState();
    final profileState = context.read<ProfileBloc>().state;
    _profileId = widget.profileId ??
        (profileState is ProfileLoaded ? profileState.activeProfileId : 'default');
  }

  Future<void> _switchProfile() async {
    final picked =
        await showProfileSwitchSheet(context: context, activeProfileId: _profileId);
    if (picked != null && picked != _profileId && mounted) {
      setState(() => _profileId = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ProfileBloc>().state;
    final profiles = profileState is ProfileLoaded ? profileState.profiles : <Profile>[];
    final profile = profiles.firstWhere(
      (p) => p.id == _profileId,
      orElse: () => Profile(
        id: _profileId,
        name: 'Server',
        settings: const ProfileSettings(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _switchProfile,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(profile.name, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              const Icon(Icons.unfold_more, size: 18),
            ],
          ),
        ),
      ),
      body: DesktopLogsPane(
        profileId: _profileId,
        selectedLogId: null,
        onLogSelected: (log) {
          if (log == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MobileDetailScreen(log: log)),
          );
        },
      ),
      bottomNavigationBar: AdBanner(adUnitId: AdConfig.bannerEndpoint),
    );
  }
}

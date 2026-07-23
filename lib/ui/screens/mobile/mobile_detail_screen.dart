import 'package:flutter/material.dart';

import '../../../domain/entities/request_log.dart';
import '../desktop/desktop_detail_pane.dart';

/// Full-screen mobile host for the request/response detail — the desktop
/// workspace's third pane, pushed as its own screen on phones. The pane
/// widget itself is fully reused; this just adds the app bar.
class MobileDetailScreen extends StatelessWidget {
  final RequestLog log;

  const MobileDetailScreen({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${log.method.name.toUpperCase()} request')),
      body: DesktopDetailPane(log: log),
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/entities/endpoint.dart';
import 'endpoint_editor/mobile_endpoint_editor.dart';

/// Thin host for the full-screen (mobile) endpoint editor. The editor UI and
/// all behavior live in [MobileEndpointEditor] / `EndpointEditorStateBase`.
class EndpointFormScreen extends StatelessWidget {
  final Endpoint? endpoint;
  final String profileId;

  const EndpointFormScreen({
    super.key,
    this.endpoint,
    this.profileId = 'default',
  });

  @override
  Widget build(BuildContext context) {
    return MobileEndpointEditor(endpoint: endpoint, profileId: profileId);
  }
}

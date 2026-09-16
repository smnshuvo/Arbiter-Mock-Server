import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/interception_mode.dart';
import '../../../domain/entities/network_condition.dart';
import '../../../domain/entities/profile.dart';
import '../../../domain/entities/request_log.dart';
import '../../../domain/usecases/server_usecases.dart';
import '../../bloc/dependency_container.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';
import '../../bloc/interception/interception_bloc.dart';
import '../../bloc/interception/interception_state.dart';
import '../../bloc/profile/profile_bloc.dart';
import '../../bloc/server/server_bloc.dart';
import '../../widgets/pass_through_url_field.dart';
import '../endpoint_editor/desktop_endpoint_editor.dart';
import '../endpoint_editor/widgets/arb_segmented.dart';
import '../endpoint_editor/widgets/network_condition_field.dart';
import 'desktop_detail_pane.dart';
import 'desktop_endpoints_pane.dart';
import 'desktop_interception_dialog.dart';
import 'desktop_settings_dialog.dart';
import 'desktop_logs_pane.dart';
import 'manage_profile_dialog.dart';
import 'server_rail.dart';

enum _MiddlePane { logs, endpoints }

/// Quick-access disclosure for port + auto pass-through, exposed by the
/// header's down-arrow toggle instead of requiring the full Manage dialog.
/// Keyed by profile id so switching profiles gets fresh controllers rather
/// than needing manual re-sync.
class _QuickSettingsPanel extends StatefulWidget {
  final Profile profile;
  final bool running;

  const _QuickSettingsPanel({required this.profile, required this.running});

  @override
  State<_QuickSettingsPanel> createState() => _QuickSettingsPanelState();
}

class _QuickSettingsPanelState extends State<_QuickSettingsPanel> {
  late final TextEditingController _portController;
  late final TextEditingController _passThroughUrlController;
  late bool _autoPassThrough;
  late NetworkCondition _networkCondition;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: widget.profile.port.toString());
    _passThroughUrlController =
        TextEditingController(text: widget.profile.settings.globalPassThroughUrl ?? '');
    _autoPassThrough = widget.profile.settings.autoPassThrough;
    _networkCondition = widget.profile.settings.networkCondition;
  }

  @override
  void dispose() {
    _portController.dispose();
    _passThroughUrlController.dispose();
    super.dispose();
  }

  void _save() {
    final port = int.tryParse(_portController.text.trim()) ?? widget.profile.port;
    context.read<ProfileBloc>().add(UpdateProfileEvent(widget.profile.copyWith(
          port: port,
          settings: widget.profile.settings.copyWith(
            autoPassThrough: _autoPassThrough,
            networkCondition: _networkCondition,
            globalPassThroughUrl: _passThroughUrlController.text.trim().isEmpty
                ? null
                : _passThroughUrlController.text.trim(),
            clearPassThroughUrl: _passThroughUrlController.text.trim().isEmpty,
          ),
          updatedAt: DateTime.now(),
        )));
  }

  /// Enter in the base URL field / picking a saved one: remember the URL
  /// (asking for a name if it's new), then persist.
  Future<void> _commitPassThroughUrl() async {
    await rememberPassThroughUrl(context, _passThroughUrlController.text);
    if (mounted) _save();
  }

  void _saveNetworkCondition(NetworkCondition c) {
    setState(() => _networkCondition = c);
    _save();
    if (widget.running) {
      context.read<ServerBloc>().add(SetProfileNetworkConditionEvent(widget.profile.id, c));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Container(
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _portController,
                  enabled: !widget.running,
                  keyboardType: TextInputType.number,
                  style: t.mono(size: 13),
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: 'Port',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    helperText: widget.running ? 'Stop to change' : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 170,
                child: NetworkConditionField(
                  value: _networkCondition,
                  onChanged: _saveNetworkCondition,
                  height: 46,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Interception', style: t.sans(size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: _autoPassThrough,
                activeThumbColor: t.accent,
                onChanged: (v) {
                  setState(() => _autoPassThrough = v);
                  _save();
                },
              ),
              const SizedBox(width: 8),
              Text('Auto pass-through',
                  style: t.sans(size: 13, weight: FontWeight.w600)),
            ],
          ),
          if (_autoPassThrough) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: ArbSegmented(
                segments: const [
                  ArbSegment('All requests'),
                  ArbSegment('Specific endpoints', enabled: false, badge: 'Soon'),
                ],
                selectedIndex: 0,
                onChanged: (_) {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 320,
                child: PassThroughUrlField(
                  controller: _passThroughUrlController,
                  dense: true,
                  onCommitted: _commitPassThroughUrl,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wide-layout workspace shown by [HomeScreen] once the window/screen crosses
/// [kWideLayoutBreakpoint]: server rail | logs feed | request/response detail,
/// with server settings and the endpoint editor tucked into a "Manage" overlay.
class DesktopWorkspaceScreen extends StatefulWidget {
  final ServerState serverState;
  final Map<String, int> endpointCounts;

  const DesktopWorkspaceScreen({
    super.key,
    required this.serverState,
    required this.endpointCounts,
  });

  @override
  State<DesktopWorkspaceScreen> createState() => _DesktopWorkspaceScreenState();
}

class _DesktopWorkspaceScreenState extends State<DesktopWorkspaceScreen> {
  String? _selectedProfileId;
  RequestLog? _selectedLog;
  bool _urlCopied = false;
  _MiddlePane _middlePane = _MiddlePane.logs;
  Endpoint? _selectedEndpoint;
  bool _creatingEndpoint = false;
  int _newEndpointSeq = 0;

  /// Prefill for the create-mode editor when it was opened from a log row.
  Endpoint? _endpointTemplate;
  bool _showQuickSettings = false;

  /// LAN address shown in the header URL while a server set to "Network" is
  /// stopped, so the Local/Network toggle previews the real URL immediately.
  String? _deviceIp;

  Future<void> _refreshDeviceIp() async {
    try {
      final ip = await sl<GetDeviceIpAddress>()();
      if (mounted && ip != _deviceIp) setState(() => _deviceIp = ip);
    } catch (_) {
      // Preview only — the server itself reports an error if it can't bind.
    }
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    setState(() => _urlCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _urlCopied = false);
    });
  }

  @override
  void initState() {
    super.initState();
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      _selectedProfileId = profileState.activeProfileId;
    }
    context.read<EndpointBloc>().add(LoadEndpointsEvent(_selectedProfileId ?? 'default'));
    _refreshDeviceIp();
  }

  Map<String, ({String url, int port})> _runningMap(ServerState state) {
    if (state is MultiServerRunning) {
      return {
        for (final srv in state.runningServers) srv.profileId: (url: srv.url, port: srv.port),
      };
    }
    if (state is ServerRunning) {
      return {state.profileId: (url: state.url, port: state.port)};
    }
    return const {};
  }

  void _selectProfile(String profileId) {
    setState(() {
      _selectedProfileId = profileId;
      _selectedLog = null;
      _selectedEndpoint = null;
      _creatingEndpoint = false;
    });
    context.read<ProfileBloc>().add(SwitchActiveProfileEvent(profileId));
    context.read<EndpointBloc>().add(LoadEndpointsEvent(profileId));
  }

  void _addEndpoint({Endpoint? template}) {
    setState(() {
      _endpointTemplate = template;
      _selectedEndpoint = null;
      _creatingEndpoint = true;
      _newEndpointSeq++;
    });
  }

  /// Opens the endpoints view, reloading that server's list first: the shared
  /// EndpointBloc may be holding a stale list (e.g. after "Add to collection"
  /// from the logs), which previously only cleared by switching servers.
  void _showEndpointsPane(String profileId) {
    context.read<EndpointBloc>().add(LoadEndpointsEvent(profileId));
    setState(() => _middlePane = _MiddlePane.endpoints);
  }

  /// "Create endpoint" from a log row's more-menu: jump to the endpoints view
  /// with the editor prefilled from that request/response.
  void _createEndpointFromLog(String profileId, RequestLog log) {
    _showEndpointsPane(profileId);
    setState(() => _selectedLog = null);
    _addEndpoint(template: _templateFromLog(profileId, log));
  }

  /// Same pattern rules as [BatchCreateEndpointsFromLogs]: path only, no query
  /// string or leading slash.
  Endpoint _templateFromLog(String profileId, RequestLog log) {
    var pattern = log.url.split('?').first;
    if (pattern.startsWith('/')) pattern = pattern.substring(1);
    final method = log.method.name.toUpperCase();
    final now = DateTime.now();
    return Endpoint(
      id: '',
      profileId: profileId,
      pattern: pattern,
      method: kEndpointMethods.contains(method) ? method : null,
      matchType: MatchType.exact,
      mode: EndpointMode.mock,
      mockResponse: (log.responseBody?.isNotEmpty ?? false) ? log.responseBody : '{}',
      statusCode: log.statusCode,
      createdAt: now,
      updatedAt: now,
    );
  }

  void _onEndpointSaved(String profileId) {
    context.read<EndpointBloc>().add(LoadEndpointsEvent(profileId));
    setState(() {
      _selectedEndpoint = null;
      _creatingEndpoint = false;
    });
  }

  StartProfileEvent _startEventFor(Profile profile) => StartProfileEvent(
        profileId: profile.id,
        profileName: profile.name,
        port: profile.port,
        useDeviceIp: profile.settings.useDeviceIp,
        passThroughUrl: profile.settings.globalPassThroughUrl,
        autoPassThrough: profile.settings.autoPassThrough,
        networkCondition: profile.settings.networkCondition,
      );

  void _toggleRun(Profile profile, bool running) {
    if (running) {
      context.read<ServerBloc>().add(StopProfileEvent(profile.id));
    } else {
      context.read<ServerBloc>().add(_startEventFor(profile));
    }
  }

  /// Header Local/Network switch. Persists the choice and, since the bind
  /// address is fixed at start, restarts a running server so the new URL is
  /// live straight away.
  void _setUseDeviceIp(Profile profile, bool useDeviceIp, bool running) {
    if (profile.settings.useDeviceIp == useDeviceIp) return;
    final updated = profile.copyWith(
      settings: profile.settings.copyWith(useDeviceIp: useDeviceIp),
      updatedAt: DateTime.now(),
    );
    context.read<ProfileBloc>().add(UpdateProfileEvent(updated));
    if (running) {
      context.read<ServerBloc>().add(RestartProfileEvent(_startEventFor(updated)));
    }
    if (useDeviceIp) _refreshDeviceIp();
  }

  void _openInterception() {
    showDialog(
      context: context,
      builder: (_) => const DesktopInterceptionDialog(),
    );
  }

  void _openManage(Profile profile) {
    showDialog(
      context: context,
      builder: (dialogContext) => ManageProfileDialog(
        profile: profile,
        onDeleted: () {
          if (profile.id == _selectedProfileId) _selectProfile('default');
        },
      ),
    );
  }

  void _showCreateProfileDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New server'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Server name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<ProfileBloc>().add(CreateProfileEvent(name: name));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runningMap = _runningMap(widget.serverState);
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        final profiles = profileState is ProfileLoaded ? profileState.profiles : <Profile>[];
        final selectedId = _selectedProfileId ?? (profiles.isNotEmpty ? profiles.first.id : 'default');
        // initState fires before the profiles finish loading, so it can only
        // load 'default' as a guess. Once the real list arrives and resolves to
        // a different first/active profile, adopt it and load its endpoints —
        // otherwise the pane asks for one server's endpoints while the bloc
        // holds another's. Runs once: after this, _selectedProfileId == selectedId.
        if (_selectedProfileId != selectedId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedProfileId == null) _selectProfile(selectedId);
          });
        }
        final selectedProfile = profiles.firstWhere(
          (p) => p.id == selectedId,
          orElse: () => Profile(
            id: 'default',
            name: 'Default',
            settings: const ProfileSettings(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        final running = runningMap.containsKey(selectedProfile.id);
        final t = ArbTokens.of(context);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 240,
              child: ServerRail(
                selectedProfileId: selectedId,
                runningMap: runningMap,
                endpointCounts: widget.endpointCounts,
                onSelect: _selectProfile,
                onCreateProfile: _showCreateProfileDialog,
                onOpenSettings: () => showDialog(
                  context: context,
                  builder: (_) => DesktopSettingsDialog(selectedProfileId: selectedId),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: t.border),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(selectedProfile, running, runningMap[selectedProfile.id]),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: (_showQuickSettings && _middlePane == _MiddlePane.logs)
                        ? _QuickSettingsPanel(profile: selectedProfile, running: running)
                        : const SizedBox(width: double.infinity),
                  ),
                  Divider(height: 1, color: t.border),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                        return ClipRect(
                          child: SlideTransition(
                            position: slide,
                            child: FadeTransition(opacity: animation, child: child),
                          ),
                        );
                      },
                      child: Row(
                        key: ValueKey(_middlePane),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _middlePane == _MiddlePane.logs
                                ? DesktopLogsPane(
                                    profileId: selectedProfile.id,
                                    selectedLogId: _selectedLog?.id,
                                    onLogSelected: (log) => setState(() => _selectedLog = log),
                                    onCreateEndpoint: (log) => _createEndpointFromLog(selectedProfile.id, log),
                                  )
                                : DesktopEndpointsPane(
                                    profileId: selectedProfile.id,
                                    profileName: selectedProfile.name,
                                    selectedEndpointId: _selectedEndpoint?.id,
                                    onEndpointSelected: (ep) => setState(() {
                                      _selectedEndpoint = ep;
                                      _creatingEndpoint = false;
                                    }),
                                    onAddEndpoint: _addEndpoint,
                                    onSelectedEndpointDeleted: () =>
                                        setState(() => _selectedEndpoint = null),
                                  ),
                          ),
                          VerticalDivider(width: 1, color: t.border),
                          Expanded(
                            flex: 4,
                            child: _middlePane == _MiddlePane.logs
                                ? DesktopDetailPane(log: _selectedLog)
                                : (_selectedEndpoint != null || _creatingEndpoint)
                                    ? DesktopEndpointEditor(
                                        key: ValueKey(
                                            _selectedEndpoint?.id ?? 'new-$_newEndpointSeq'),
                                        endpoint: _selectedEndpoint,
                                        template: _endpointTemplate,
                                        profileId: selectedProfile.id,
                                        onSaved: () => _onEndpointSaved(selectedProfile.id),
                                      )
                                    : _buildEndpointsEmptyState(t),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEndpointsEmptyState(ArbTokens t) {
    return Container(
      color: t.canvas,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rule, size: 48, color: t.textMuted),
            const SizedBox(height: 10),
            Text('Select an endpoint to edit, or add a new one',
                style: t.sans(size: 13, color: t.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Profile profile, bool running, ({String url, int port})? runningInfo) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildHeaderRow(profile, running, runningInfo, compact: constraints.maxWidth < 1000),
    );
  }

  Widget _buildHeaderRow(
    Profile profile,
    bool running,
    ({String url, int port})? runningInfo, {
    required bool compact,
  }) {
    final t = ArbTokens.of(context);
    final useDeviceIp = profile.settings.useDeviceIp;
    final previewHost = useDeviceIp ? (_deviceIp ?? '0.0.0.0') : 'localhost';
    final url = runningInfo?.url ?? 'http://$previewHost:${profile.port}';
    final inEndpoints = _middlePane == _MiddlePane.endpoints;
    return Container(
      color: t.surface,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          if (inEndpoints)
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, color: t.textSecondary),
              onPressed: () => setState(() => _middlePane = _MiddlePane.logs),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                'assets/app_icon/app_icon.png',
                width: 22,
                height: 22,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(width: 10),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: running ? t.green : t.textMuted,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name,
                    overflow: TextOverflow.ellipsis,
                    style: t.sans(size: 16, weight: FontWeight.w700)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Tooltip(
                          message: running
                              ? 'Switching restarts the server on the new address'
                              : 'Bind to localhost only, or to the network (0.0.0.0)',
                          child: ArbSegmented(
                            compact: true,
                            segments: const [ArbSegment('Local'), ArbSegment('Network')],
                            selectedIndex: useDeviceIp ? 1 : 0,
                            onChanged: (i) => _setUseDeviceIp(profile, i == 1, running),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(url,
                          overflow: TextOverflow.ellipsis, style: t.mono(size: 11.5, color: t.textMuted)),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => _copyUrl(url),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Text(_urlCopied ? 'Copied' : 'Copy',
                            style: t.sans(
                                size: 11, weight: FontWeight.w700, color: t.accent)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _toggleRun(profile, running),
            style: FilledButton.styleFrom(
              backgroundColor: running ? const Color(0xFFDC2626) : t.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
            ),
            child: Text(running ? 'Stop' : 'Run',
                style: t.sans(size: 12.5, weight: FontWeight.w700, color: Colors.white)),
          ),
          if (!inEndpoints) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: _showQuickSettings ? 'Hide port & pass-through' : 'Show port & pass-through',
              icon: Icon(
                _showQuickSettings ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: t.textSecondary,
              ),
              onPressed: () => setState(() => _showQuickSettings = !_showQuickSettings),
            ),
            const SizedBox(width: 4),
            if (compact)
              IconButton(
                tooltip: 'Manage endpoints',
                icon: Icon(Icons.rule, color: t.textSecondary),
                onPressed: () => _showEndpointsPane(profile.id),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showEndpointsPane(profile.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.textSecondary,
                  side: BorderSide(color: t.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
                ),
                icon: const Icon(Icons.rule, size: 18),
                label: Text('Manage endpoints', style: t.sans(size: 12.5)),
              ),
          ],
          const SizedBox(width: 8),
          _buildInterceptionButton(t, compact: compact),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Manage server',
            icon: Icon(Icons.settings_outlined, color: t.textSecondary),
            onPressed: () => _openManage(profile),
          ),
        ],
      ),
    );
  }

  /// Always-visible interception control: shows whether requests are being
  /// held (and which direction) and opens [DesktopInterceptionDialog].
  Widget _buildInterceptionButton(ArbTokens t, {required bool compact}) {
    return BlocBuilder<InterceptionBloc, InterceptionState>(
      builder: (context, state) {
        final mode = currentInterceptionMode(state);
        final on = mode != InterceptionMode.none;
        final label = switch (mode) {
          InterceptionMode.none => 'Intercept off',
          InterceptionMode.requestOnly => 'Intercepting requests',
          InterceptionMode.responseOnly => 'Intercepting responses',
          InterceptionMode.both => 'Intercepting',
        };
        final color = on ? t.accent : t.textSecondary;
        final icon = Icon(on ? Icons.pause_circle : Icons.pause_circle_outline, size: 18, color: color);
        if (compact) {
          return IconButton(
            tooltip: label,
            icon: Icon(icon.icon, color: color),
            onPressed: _openInterception,
          );
        }
        return OutlinedButton.icon(
          onPressed: _openInterception,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            backgroundColor: on ? t.accentSoft : null,
            side: BorderSide(color: on ? t.accent : t.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSm)),
          ),
          icon: icon,
          label: Text(label, style: t.sans(size: 12.5, color: color)),
        );
      },
    );
  }
}

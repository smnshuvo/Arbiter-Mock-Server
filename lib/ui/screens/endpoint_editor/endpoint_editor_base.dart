import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/endpoint.dart';
import '../../bloc/endpoint/endpoint_bloc.dart';
import '../conditional_mock_screen.dart';
import 'widgets/arb_mode_card.dart';
import 'widgets/arb_section_label.dart';
import 'widgets/arb_segmented.dart';
import 'widgets/delay_stepper.dart';
import 'widgets/json_brace_controller.dart';
import 'widgets/json_code_editor.dart';
import 'widgets/json_form_editor.dart';
import 'widgets/status_field.dart';

enum _BodyTab { form, code }

/// Base widget for the endpoint editor. Concrete subclasses
/// ([MobileEndpointEditor], [DesktopEndpointEditor]) only differ in how they
/// arrange the shared section builders — all state and behavior lives in
/// [EndpointEditorStateBase].
abstract class EndpointEditorBase extends StatefulWidget {
  const EndpointEditorBase({
    super.key,
    this.endpoint,
    this.profileId = 'default',
    this.onSaved,
  });

  /// Null → create mode; non-null → edit mode.
  final Endpoint? endpoint;
  final String profileId;

  /// Called after a successful save. When provided (desktop pane) the editor
  /// stays mounted; when null (mobile) the editor pops itself.
  final VoidCallback? onSaved;
}

abstract class EndpointEditorStateBase<T extends EndpointEditorBase>
    extends State<T> {
  late final TextEditingController patternController;
  late final TextEditingController mockResponseController;
  late final TextEditingController targetUrlController;
  late final TextEditingController statusController;

  String? method; // null = ANY
  late MatchType matchType;
  late EndpointMode mode;
  int delayMs = 0;
  bool useConditionalMock = false;
  late List<ConditionalMock> conditionalMocks;

  _BodyTab _bodyTab = _BodyTab.form;
  int _formEpoch = 0; // bumped so the form re-reads the controller after Code edits
  bool _pendingCreate = false;

  bool get isEditing => widget.endpoint == null ? false : true;
  bool get isMock => mode == EndpointMode.mock;
  bool get isPassThrough => mode == EndpointMode.passThrough;

  String get editorTitle =>
      widget.endpoint == null ? 'New endpoint' : 'Edit endpoint';

  @override
  void initState() {
    super.initState();
    final e = widget.endpoint;
    patternController = TextEditingController(text: e?.pattern ?? '');
    mockResponseController =
        JsonBraceController(text: e?.mockResponse ?? '{}');
    targetUrlController = TextEditingController(text: e?.targetUrl ?? '');
    statusController =
        TextEditingController(text: (e?.statusCode ?? 200).toString());
    method = e?.method;
    matchType = e?.matchType ?? MatchType.exact;
    mode = e?.mode ?? EndpointMode.mock;
    delayMs = e?.delayMs ?? 0;
    useConditionalMock = e?.useConditionalMock ?? false;
    conditionalMocks = List.from(e?.conditionalMocks ?? const []);
    // Start on the Code tab if the stored body can't be parsed into a tree.
    if (!_isJson(mockResponseController.text)) _bodyTab = _BodyTab.code;
  }

  @override
  void dispose() {
    patternController.dispose();
    mockResponseController.dispose();
    targetUrlController.dispose();
    statusController.dispose();
    super.dispose();
  }

  bool _isJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return true;
    try {
      jsonDecode(trimmed);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- Build layout (implemented by subclasses) ----
  Widget buildLayout(BuildContext context);

  @override
  Widget build(BuildContext context) {
    return BlocListener<EndpointBloc, EndpointState>(
      listener: (context, state) {
        if (state is EndpointLoaded && _pendingCreate) {
          _pendingCreate = false;
          _handleSaved();
        } else if (state is EndpointDuplicateFound) {
          _pendingCreate = false;
          _showUpdatePrompt(state.existing, state.incoming);
        } else if (state is EndpointError && _pendingCreate) {
          _pendingCreate = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      child: buildLayout(context),
    );
  }

  // ---- Save flow ----
  Endpoint buildEndpoint() {
    final now = DateTime.now();
    return Endpoint(
      id: widget.endpoint?.id ?? now.millisecondsSinceEpoch.toString(),
      profileId: widget.endpoint?.profileId ?? widget.profileId,
      pattern: patternController.text.trim(),
      method: method,
      matchType: matchType,
      mode: mode,
      mockResponse: isMock
          ? (mockResponseController.text.isEmpty
              ? '{}'
              : mockResponseController.text)
          : null,
      statusCode:
          isMock ? (int.tryParse(statusController.text.trim()) ?? 200) : 200,
      delayMs: isMock ? delayMs : 0,
      targetUrl: isPassThrough ? targetUrlController.text.trim() : null,
      createdAt: widget.endpoint?.createdAt ?? now,
      updatedAt: now,
      isEnabled: widget.endpoint?.isEnabled ?? true,
      useConditionalMock: isMock ? useConditionalMock : false,
      conditionalMocks:
          isMock && useConditionalMock ? conditionalMocks : const [],
    );
  }

  void save() {
    if (patternController.text.trim().isEmpty) {
      _snack('Please enter a URL pattern');
      return;
    }
    if (isPassThrough) {
      final target = targetUrlController.text.trim();
      if (target.isEmpty) {
        _snack('Please enter a target URL');
        return;
      }
      if (!target.startsWith('http')) {
        _snack('URL must start with http:// or https://');
        return;
      }
    }

    final endpoint = buildEndpoint();
    if (widget.endpoint == null) {
      _pendingCreate = true;
      context.read<EndpointBloc>().add(CreateEndpointEvent(endpoint));
      // _handleSaved fires from the BlocListener on EndpointLoaded / duplicate.
    } else {
      context.read<EndpointBloc>().add(UpdateEndpointEvent(endpoint));
      _handleSaved();
    }
  }

  void _handleSaved() {
    if (widget.onSaved != null) {
      widget.onSaved!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showUpdatePrompt(Endpoint existing, Endpoint incoming) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Endpoint Already Exists'),
        content: Text(
          'An endpoint with pattern "${existing.pattern}" already exists in '
          'this profile. Do you want to update it instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<EndpointBloc>().add(UpdateEndpointEvent(
                    incoming.copyWith(
                        id: existing.id, createdAt: existing.createdAt),
                  ));
              _handleSaved();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _openConditionalScreen() async {
    final result = await Navigator.push<List<ConditionalMock>>(
      context,
      MaterialPageRoute(
        builder: (_) => ConditionalMockScreen(conditionalMocks: conditionalMocks),
      ),
    );
    if (result != null) {
      setState(() => conditionalMocks = result);
    }
  }

  // =====================================================================
  // Shared section builders — composed differently by each layout.
  // =====================================================================

  Widget buildMethodPathRow() {
    final t = ArbTokens.of(context);
    return Row(
      children: [
        _methodButton(t),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 46,
            child: TextField(
              controller: patternController,
              style: t.mono(size: 14),
              decoration: InputDecoration(
                hintText: '/v1/resource',
                hintStyle: t.mono(size: 14, color: t.textMuted),
                filled: true,
                fillColor: t.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 13),
                border: _inputBorder(t, t.border),
                enabledBorder: _inputBorder(t, t.border),
                focusedBorder: _inputBorder(t, t.accent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _methodButton(ArbTokens t) {
    final label = method ?? 'ANY';
    final color = _methodColor(t, label);
    return PopupMenuButton<String>(
      tooltip: 'HTTP method',
      onSelected: (v) => setState(() => method = v == 'ANY' ? null : v),
      itemBuilder: (_) => [
        for (final m in kEndpointMethods)
          PopupMenuItem(value: m, child: Text(m)),
      ],
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(t.radius - 1),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: t.mono(size: 13, weight: FontWeight.w700, color: color)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Color _methodColor(ArbTokens t, String method) {
    switch (method) {
      case 'GET':
        return t.green;
      case 'POST':
        return const Color(0xFF2563EB);
      case 'PUT':
        return const Color(0xFFF59E0B);
      case 'PATCH':
        return t.purple;
      case 'DELETE':
        return const Color(0xFFDC2626);
      default:
        return t.textSecondary;
    }
  }

  Widget buildMatchType() {
    return ArbSegmented(
      segments: const [
        ArbSegment('Exact'),
        ArbSegment('Wildcard'),
        ArbSegment('Regex'),
      ],
      selectedIndex: matchType.index,
      onChanged: (i) => setState(() => matchType = MatchType.values[i]),
    );
  }

  Widget buildModeSelector() {
    return Row(
      children: [
        Expanded(
          child: ArbModeCard(
            title: 'Mock',
            subtitle: 'Static JSON',
            selected: mode == EndpointMode.mock,
            onTap: () => setState(() => mode = EndpointMode.mock),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ArbModeCard(
            title: 'Code exec',
            subtitle: 'Run JS',
            selected: false,
            enabled: false,
            badge: 'Soon',
            onTap: () {},
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ArbModeCard(
            title: 'Pass-through',
            subtitle: 'Forward',
            selected: mode == EndpointMode.passThrough,
            onTap: () => setState(() => mode = EndpointMode.passThrough),
          ),
        ),
      ],
    );
  }

  Widget buildStatusField() =>
      StatusField(controller: statusController, onChanged: (_) {});

  Widget buildDelayStepper() => DelayStepper(
        valueMs: delayMs,
        onChanged: (v) => setState(() => delayMs = v),
      );

  /// Compact conditional toggle (label + switch) — used inline on desktop.
  Widget buildConditionalToggle() {
    final t = ArbTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Conditional',
            style: t.sans(size: 12, color: t.textSecondary)),
        Switch(
          value: useConditionalMock,
          activeThumbColor: t.accent,
          onChanged: (v) => setState(() => useConditionalMock = v),
        ),
      ],
    );
  }

  /// Full conditional card (toggle + description) — used on mobile.
  Widget buildConditionalCard() {
    final t = ArbTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conditional responses',
                    style: t.sans(size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Return different bodies by query or body field.',
                    style: t.sans(size: 12, color: t.textSecondary)),
              ],
            ),
          ),
          Switch(
            value: useConditionalMock,
            activeThumbColor: t.accent,
            onChanged: (v) => setState(() => useConditionalMock = v),
          ),
        ],
      ),
    );
  }

  /// Opener row for the (separate) conditional mock screen. Only meaningful
  /// when [useConditionalMock] is on.
  Widget buildConditionalSummary() {
    final t = ArbTokens.of(context);
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius),
        onTap: _openConditionalScreen,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(t.radius),
          ),
          child: Row(
            children: [
              Icon(Icons.rule, size: 18, color: t.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${conditionalMocks.length} condition'
                  '${conditionalMocks.length == 1 ? '' : 's'} · tap to manage',
                  style: t.sans(size: 13, weight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildResponseBodyHeader() {
    return Row(
      children: [
        const ArbSectionLabel('Response body', padding: EdgeInsets.zero),
        const Spacer(),
        SizedBox(
          width: 168,
          child: ArbSegmented(
            compact: true,
            segments: const [
              ArbSegment('▦ Form'),
              ArbSegment('</> Code'),
            ],
            selectedIndex: _bodyTab.index,
            onChanged: (i) {
              setState(() {
                final next = _BodyTab.values[i];
                // Re-read the controller into a fresh tree when returning to Form.
                if (next == _BodyTab.form) _formEpoch++;
                _bodyTab = next;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget buildResponseBody() {
    final t = ArbTokens.of(context);

    if (_bodyTab == _BodyTab.code) {
      return JsonCodeEditor(
        controller: mockResponseController,
        onChanged: (_) {},
      );
    }

    // Form tab.
    if (_isJson(mockResponseController.text)) {
      return JsonFormEditor(
        key: ValueKey(_formEpoch),
        initialJson: mockResponseController.text,
        onChanged: (json) => mockResponseController.text = json,
      );
    }

    // Body isn't parseable — steer the user to the Code tab.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x14DC2626),
        border: Border.all(color: const Color(0x33DC2626)),
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This body isn\'t valid JSON yet, so the visual editor can\'t show it.',
            style: t.sans(size: 12.5, color: const Color(0xFFB4432B)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _bodyTab = _BodyTab.code),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: t.surface,
            ),
            child: Text('Edit in Code',
                style: t.sans(size: 12, weight: FontWeight.w700, color: t.accent)),
          ),
        ],
      ),
    );
  }

  Widget buildPassThrough() {
    final t = ArbTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ArbSectionLabel('Target URL'),
        TextField(
          controller: targetUrlController,
          style: t.mono(size: 13),
          decoration: InputDecoration(
            hintText: 'https://api.example.com/v1/resource',
            hintStyle: t.mono(size: 13, color: t.textMuted),
            filled: true,
            fillColor: t.surface,
            contentPadding: const EdgeInsets.all(13),
            border: _inputBorder(t, t.border),
            enabledBorder: _inputBorder(t, t.border),
            focusedBorder: _inputBorder(t, t.accent),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surfaceMuted,
            borderRadius: BorderRadius.circular(t.radius - 1),
          ),
          child: Text(
            'Requests to this endpoint are forwarded to the target and the live '
            'response is returned unchanged.',
            style: t.sans(size: 12, color: t.textSecondary),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _inputBorder(ArbTokens t, Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radius - 1),
        borderSide: BorderSide(color: color),
      );
}

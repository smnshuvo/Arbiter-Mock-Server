import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import 'endpoint_editor_base.dart';
import 'widgets/arb_section_label.dart';

/// Full-screen mobile layout of the endpoint editor: a sticky header over a
/// single scrolling column of sections.
class MobileEndpointEditor extends EndpointEditorBase {
  const MobileEndpointEditor({
    super.key,
    super.endpoint,
    super.profileId,
    super.onSaved,
  });

  @override
  State<MobileEndpointEditor> createState() => _MobileEndpointEditorState();
}

class _MobileEndpointEditorState
    extends EndpointEditorStateBase<MobileEndpointEditor> {
  @override
  Widget buildLayout(BuildContext context) {
    final t = ArbTokens.of(context);
    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(t),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _sections(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ArbTokens t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
      color: t.canvas,
      child: Row(
        children: [
          _squareButton(t, Icons.close, () {
            if (Navigator.canPop(context)) Navigator.pop(context);
          }),
          const SizedBox(width: 10),
          Expanded(
            child: Text(editorTitle,
                style: t.sans(size: 16, weight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: save,
            style: FilledButton.styleFrom(
              backgroundColor: t.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.radius - 2),
              ),
            ),
            child: Text('Save',
                style: t.sans(
                    size: 13, weight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections() {
    return [
      buildMethodPathRow(),
      const SizedBox(height: 18),
      const ArbSectionLabel('Match type'),
      buildMatchType(),
      const SizedBox(height: 18),
      const ArbSectionLabel('Mode'),
      buildModeSelector(),
      const SizedBox(height: 18),
      if (isMock) ..._mockSections() else buildPassThrough(),
    ];
  }

  List<Widget> _mockSections() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ArbSectionLabel('Status'),
                buildStatusField(),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ArbSectionLabel('Delay'),
                buildDelayStepper(),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      buildResponseBodyHeader(),
      const SizedBox(height: 10),
      buildResponseBody(),
      const SizedBox(height: 20),
      buildConditionalCard(),
      if (useConditionalMock) ...[
        const SizedBox(height: 9),
        buildConditionalSummary(),
      ],
    ];
  }

  Widget _squareButton(ArbTokens t, IconData icon, VoidCallback onTap) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(t.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radiusSm),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(t.radiusSm),
            border: Border.all(color: t.border),
          ),
          child: Icon(icon, size: 18, color: t.textSecondary),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import 'endpoint_editor_base.dart';
import 'widgets/arb_section_label.dart';

/// Desktop pane layout of the endpoint editor: a header row plus sections
/// arranged in horizontal groupings (match+mode, status+delay+conditional).
/// Embedded in the endpoints workspace right pane; saving keeps the pane open.
class DesktopEndpointEditor extends EndpointEditorBase {
  const DesktopEndpointEditor({
    super.key,
    super.endpoint,
    super.profileId,
    super.onSaved,
  });

  @override
  State<DesktopEndpointEditor> createState() => _DesktopEndpointEditorState();
}

class _DesktopEndpointEditorState
    extends EndpointEditorStateBase<DesktopEndpointEditor> {
  @override
  Widget buildLayout(BuildContext context) {
    final t = ArbTokens.of(context);
    return Container(
      color: t.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(t),
            const SizedBox(height: 18),
            buildMethodPathRow(),
            const SizedBox(height: 16),
            _matchAndMode(),
            const SizedBox(height: 16),
            if (isMock) ..._mockSections() else buildPassThrough(),
          ],
        ),
      ),
    );
  }

  Widget _header(ArbTokens t) {
    return Row(
      children: [
        Expanded(
          child: Text(editorTitle,
              style: t.sans(size: 16, weight: FontWeight.w700)),
        ),
        FilledButton(
          onPressed: save,
          style: FilledButton.styleFrom(
            backgroundColor: t.accent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.radiusSm),
            ),
          ),
          child: Text(isEditing ? 'Save changes' : 'Create endpoint',
              style: t.sans(
                  size: 12, weight: FontWeight.w700, color: Colors.white)),
        ),
      ],
    );
  }

  Widget _matchAndMode() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ArbSectionLabel('Match type'),
              buildMatchType(),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ArbSectionLabel('Mode'),
              buildModeSelector(),
            ],
          ),
        ),
      ],
    );
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ArbSectionLabel('Delay'),
                buildDelayStepper(),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: buildConditionalToggle(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      buildResponseBodyHeader(),
      const SizedBox(height: 10),
      buildResponseBody(),
      if (useConditionalMock) ...[
        const SizedBox(height: 14),
        buildConditionalSummary(),
      ],
    ];
  }
}

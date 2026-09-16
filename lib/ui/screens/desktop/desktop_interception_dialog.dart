import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/interception_mode.dart';
import '../../../domain/usecases/interception_usecases.dart';
import '../../bloc/dependency_container.dart';
import '../../bloc/interception/interception_bloc.dart';
import '../../bloc/interception/interception_event.dart';
import '../../bloc/interception/interception_state.dart';
import '../endpoint_editor/widgets/arb_section_label.dart';
import '../endpoint_editor/widgets/arb_segmented.dart';

/// Reads the live interception mode. [InterceptionState] only carries the
/// mode on Enabled/Pending — the transient Processing/Completed states drop
/// it — so fall back to the repository, which is the source of truth.
InterceptionMode currentInterceptionMode(InterceptionState state) {
  if (state is InterceptionEnabled) return state.mode;
  if (state is InterceptionPending) return state.mode;
  if (state is InterceptionDisabled) return InterceptionMode.none;
  return sl<GetInterceptionMode>()();
}

/// Wide-layout counterpart to the Settings screen's "Real-time Interception"
/// card, opened from the workspace header. Interception is global — it
/// applies to every running server, not just the selected one. Pending
/// intercepts themselves still surface through [HomeScreen]'s dialog.
class DesktopInterceptionDialog extends StatefulWidget {
  const DesktopInterceptionDialog({super.key});

  @override
  State<DesktopInterceptionDialog> createState() => _DesktopInterceptionDialogState();
}

class _DesktopInterceptionDialogState extends State<DesktopInterceptionDialog> {
  static const _modes = [
    InterceptionMode.none,
    InterceptionMode.requestOnly,
    InterceptionMode.responseOnly,
    InterceptionMode.both,
  ];

  final TextEditingController _patternController = TextEditingController();

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  void _addPattern(List<String> current) {
    final pattern = _patternController.text.trim();
    if (pattern.isEmpty || current.contains(pattern)) return;
    context.read<InterceptionBloc>().add(SetInterceptionWhitelistEvent([...current, pattern]));
    _patternController.clear();
  }

  void _removePattern(List<String> current, String pattern) {
    context.read<InterceptionBloc>().add(
          SetInterceptionWhitelistEvent(current.where((p) => p != pattern).toList()),
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Dialog(
      backgroundColor: t.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: BlocBuilder<InterceptionBloc, InterceptionState>(
          builder: (context, state) {
            final mode = currentInterceptionMode(state);
            final enabled = mode != InterceptionMode.none;
            final patterns = sl<GetInterceptionWhitelist>()();
            final isBlacklist = sl<GetUrlListMode>()() == UrlListMode.blacklist;
            final timeout = sl<GetInterceptionTimeout>()();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Interception',
                            style: t.sans(size: 15, weight: FontWeight.w700)),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: t.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: t.border),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Pause matching requests and/or responses so you can inspect '
                          'and edit them before they continue. Applies to every running '
                          'server; unanswered holds continue after ${timeout}s.',
                          style: t.sans(
                              size: 12, weight: FontWeight.w500, color: t.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        const ArbSectionLabel('Intercept'),
                        ArbSegmented(
                          segments: const [
                            ArbSegment('Off'),
                            ArbSegment('Requests'),
                            ArbSegment('Responses'),
                            ArbSegment('Both'),
                          ],
                          selectedIndex: _modes.indexOf(mode),
                          onChanged: (i) => context
                              .read<InterceptionBloc>()
                              .add(SetInterceptionModeEvent(_modes[i])),
                        ),
                        if (enabled) ...[
                          const SizedBox(height: 20),
                          const ArbSectionLabel('URL filter'),
                          ArbSegmented(
                            segments: const [
                              ArbSegment('Only matching'),
                              ArbSegment('All except matching'),
                            ],
                            selectedIndex: isBlacklist ? 1 : 0,
                            onChanged: (i) => context.read<InterceptionBloc>().add(
                                  SetUrlListModeEvent(
                                      i == 1 ? UrlListMode.blacklist : UrlListMode.whitelist),
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            patterns.isEmpty
                                ? 'No patterns — every URL is intercepted. Supports * wildcards.'
                                : (isBlacklist
                                    ? 'URLs matching a pattern below are NOT intercepted.'
                                    : 'Only URLs matching a pattern below are intercepted.'),
                            style: t.sans(
                                size: 11.5, weight: FontWeight.w500, color: t.textMuted),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _patternController,
                                  style: t.mono(size: 12.5),
                                  onSubmitted: (_) => _addPattern(patterns),
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. */api/users*',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Add pattern',
                                icon: Icon(Icons.add_circle, color: t.accent),
                                onPressed: () => _addPattern(patterns),
                              ),
                            ],
                          ),
                          if (patterns.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final pattern in patterns)
                                  Chip(
                                    label: Text(pattern, style: t.mono(size: 11.5)),
                                    onDeleted: () => _removePattern(patterns, pattern),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

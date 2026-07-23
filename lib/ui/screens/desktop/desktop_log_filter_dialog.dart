import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/request_log.dart';
import '../../../domain/repositories/log_repository.dart';

/// ArbTokens-styled filter dialog for the logs pane — used on both the
/// desktop 3-pane workspace and [MobileLogsScreen].
class DesktopLogFilterDialog extends StatefulWidget {
  final LogFilter? currentFilter;
  final List<String> availableIps;

  const DesktopLogFilterDialog({
    super.key,
    this.currentFilter,
    this.availableIps = const [],
  });

  @override
  State<DesktopLogFilterDialog> createState() => _DesktopLogFilterDialogState();
}

class _DesktopLogFilterDialogState extends State<DesktopLogFilterDialog> {
  late Set<RequestMethod> _methods;
  late Set<int> _statusCodes;
  late Set<LogType> _logTypes;
  String? _ip;
  DateTime? _startDate;
  DateTime? _endDate;

  static const _statusGroups = [
    ('2xx', [200, 201, 204]),
    ('3xx', [301, 302, 304]),
    ('4xx', [400, 401, 403, 404]),
    ('5xx', [500, 502, 503]),
  ];

  @override
  void initState() {
    super.initState();
    _methods = widget.currentFilter?.methods?.toSet() ?? {};
    _statusCodes = widget.currentFilter?.statusCodes?.toSet() ?? {};
    _logTypes = widget.currentFilter?.logTypes?.toSet() ?? {};
    _ip = widget.currentFilter?.ip;
    _startDate = widget.currentFilter?.startDate;
    _endDate = widget.currentFilter?.endDate;
  }

  bool get _hasFilters =>
      _methods.isNotEmpty ||
      _statusCodes.isNotEmpty ||
      _logTypes.isNotEmpty ||
      _ip != null ||
      _startDate != null ||
      _endDate != null;

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    return Dialog(
      backgroundColor: t.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          children: [
            _header(t),
            Divider(height: 1, color: t.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(t, 'METHOD', _methodChips(t)),
                    const SizedBox(height: 20),
                    _section(t, 'STATUS', _statusChips(t)),
                    const SizedBox(height: 20),
                    _section(t, 'TYPE', _typeChips(t)),
                    if (widget.availableIps.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _section(t, 'CLIENT IP', _ipChips(t)),
                    ],
                    const SizedBox(height: 20),
                    _section(t, 'DATE RANGE', _dateRangeRow(t)),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: t.border),
            _footer(t),
          ],
        ),
      ),
    );
  }

  Widget _header(ArbTokens t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Row(
          children: [
            Expanded(
                child: Text('Filter requests',
                    style: t.sans(size: 15, weight: FontWeight.w700))),
            IconButton(
              icon: Icon(Icons.close, color: t.textSecondary),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );

  Widget _section(ArbTokens t, String label, Widget content) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.label),
          const SizedBox(height: 10),
          content,
        ],
      );

  Widget _chip(ArbTokens t, String label, bool selected, VoidCallback onTap,
      {Color? accent}) {
    final color = accent ?? t.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(t.radiusSm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : t.surfaceMuted,
          border: Border.all(color: selected ? color : t.border),
          borderRadius: BorderRadius.circular(t.radiusSm),
        ),
        child: Text(label,
            style: t.mono(
                size: 11.5,
                weight: FontWeight.w700,
                color: selected ? color : t.textSecondary)),
      ),
    );
  }

  Widget _methodChips(ArbTokens t) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: RequestMethod.values.map((m) {
          final label = m.name.toUpperCase();
          return _chip(t, label, _methods.contains(m), () {
            setState(() {
              if (_methods.contains(m)) {
                _methods.remove(m);
              } else {
                _methods.add(m);
              }
            });
          }, accent: t.methodColor(label));
        }).toList(),
      );

  Widget _statusChips(ArbTokens t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _statusGroups.map((g) {
          final (_, codes) = g;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in codes)
                  _chip(t, '$code', _statusCodes.contains(code), () {
                    setState(() {
                      if (_statusCodes.contains(code)) {
                        _statusCodes.remove(code);
                      } else {
                        _statusCodes.add(code);
                      }
                    });
                  }, accent: t.statusColor(code)),
              ],
            ),
          );
        }).toList(),
      );

  Widget _typeChips(ArbTokens t) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: LogType.values.map((type) {
          final label = type == LogType.mock ? 'Mock' : 'Pass-through';
          return _chip(t, label, _logTypes.contains(type), () {
            setState(() {
              if (_logTypes.contains(type)) {
                _logTypes.remove(type);
              } else {
                _logTypes.add(type);
              }
            });
          });
        }).toList(),
      );

  Widget _ipChips(ArbTokens t) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip(t, 'All', _ip == null, () => setState(() => _ip = null)),
          for (final ip in widget.availableIps)
            _chip(t, ip, _ip == ip,
                () => setState(() => _ip = _ip == ip ? null : ip)),
        ],
      );

  Widget _dateRangeRow(ArbTokens t) => Row(
        children: [
          Expanded(child: _dateField(t, 'Start', _startDate, (d) => setState(() => _startDate = d))),
          const SizedBox(width: 10),
          Expanded(child: _dateField(t, 'End', _endDate, (d) => setState(() => _endDate = d))),
          if (_startDate != null || _endDate != null)
            IconButton(
              tooltip: 'Clear dates',
              icon: Icon(Icons.close, size: 16, color: t.textMuted),
              onPressed: () => setState(() {
                _startDate = null;
                _endDate = null;
              }),
            ),
        ],
      );

  Widget _dateField(
      ArbTokens t, String label, DateTime? value, ValueChanged<DateTime?> onPicked) {
    return InkWell(
      borderRadius: BorderRadius.circular(t.radiusSm),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (date != null) onPicked(date);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(t.radiusSm),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 13, color: t.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null ? value.toString().split(' ').first : label,
                overflow: TextOverflow.ellipsis,
                style: t.mono(size: 11.5, color: value != null ? t.textPrimary : t.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ArbTokens t) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            TextButton(
              onPressed: _hasFilters
                  ? () => setState(() {
                        _methods.clear();
                        _statusCodes.clear();
                        _logTypes.clear();
                        _ip = null;
                        _startDate = null;
                        _endDate = null;
                      })
                  : null,
              child: Text('Clear all',
                  style: t.sans(size: 12.5, weight: FontWeight.w700, color: t.textSecondary)),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                LogFilter(
                  methods: _methods.isEmpty ? null : _methods.toList(),
                  statusCodes: _statusCodes.isEmpty ? null : _statusCodes.toList(),
                  logTypes: _logTypes.isEmpty ? null : _logTypes.toList(),
                  startDate: _startDate,
                  endDate: _endDate,
                  ip: _ip,
                ),
              ),
              style: FilledButton.styleFrom(backgroundColor: t.accent),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
}

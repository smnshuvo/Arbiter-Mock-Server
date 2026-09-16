import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../../core/theme/arbiter_tokens.dart';
import '../../../domain/entities/request_log.dart';
import '../endpoint_editor/widgets/json_body_viewer.dart';
import '../json_docs/android_json_editor_screen.dart';
import '../json_docs/json_docs_controller.dart';
import '../json_docs/json_docs_screen.dart';

/// Right pane of the wide-layout workspace: request/response detail for the
/// selected log row, or an empty state when nothing is selected. Also reused
/// as the body of [MobileDetailScreen] on phones.
class DesktopDetailPane extends StatefulWidget {
  final RequestLog? log;

  const DesktopDetailPane({super.key, required this.log});

  @override
  State<DesktopDetailPane> createState() => _DesktopDetailPaneState();
}

class _DesktopDetailPaneState extends State<DesktopDetailPane> {
  // Headers are usually noise next to the body — start collapsed.
  bool _headersExpanded = false;

  void _openInEditor(String title, String content, String filenameBase) {
    JsonDocsController.instance
        .openInMemory(title: title, content: content, filenameBase: filenameBase);
    final screen =
        Platform.isAndroid ? const AndroidJsonEditorScreen() : const JsonDocsScreen();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  /// Filename-safe stand-in for "endpoint name" — the request path is the
  /// closest thing a log has to one.
  String _filenameBase(RequestLog log, String suffix) {
    final path = _displayPath(log.url).replaceFirst(RegExp(r'^/'), '');
    final safe = path.isEmpty ? 'root' : path.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${safe}_$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final t = ArbTokens.of(context);
    final log = widget.log;
    if (log == null) {
      return Container(
        color: t.canvas,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swap_horiz, size: 48, color: t.textMuted),
              const SizedBox(height: 10),
              Text('Select a request to view details',
                  style: t.sans(size: 13, color: t.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: t.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _methodChip(t, log.method.name.toUpperCase()),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_displayPath(log.url),
                        style: t.mono(size: 14, weight: FontWeight.w700))),
                _statusChip(t, log.statusCode),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${log.timestamp} · ${log.responseTimeMs}ms · '
              '${log.logType == LogType.mock ? 'mock' : 'pass-through'}',
              style: t.mono(size: 11.5, color: t.textMuted),
            ),
            if (log.ip != null) ...[
              const SizedBox(height: 10),
              _deviceChip(t, log),
            ],
            const SizedBox(height: 18),
            InkWell(
              onTap: () => setState(() => _headersExpanded = !_headersExpanded),
              child: Row(
                children: [
                  Text('HEADERS', style: t.label),
                  const SizedBox(width: 4),
                  Icon(_headersExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: t.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _headersExpanded
                  ? _plainBox(
                      t, log.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'))
                  : const SizedBox(width: double.infinity),
            ),
            if (log.requestBody != null && log.requestBody!.isNotEmpty) ...[
              const SizedBox(height: 16),
              JsonBodyViewer(
                label: 'REQUEST BODY',
                jsonString: log.requestBody!,
                onOpenInEditor: () => _openInEditor(
                    '${log.method.name.toUpperCase()} ${_displayPath(log.url)} · request',
                    log.requestBody!,
                    _filenameBase(log, 'request')),
              ),
            ],
            const SizedBox(height: 16),
            if (log.responseBody != null && log.responseBody!.isNotEmpty)
              JsonBodyViewer(
                label: 'RESPONSE BODY',
                jsonString: log.responseBody!,
                onOpenInEditor: () => _openInEditor(
                    '${log.method.name.toUpperCase()} ${_displayPath(log.url)} · response',
                    log.responseBody!,
                    _filenameBase(log, 'response')),
              )
            else ...[
              Text('RESPONSE BODY', style: t.label),
              const SizedBox(height: 8),
              _plainBox(t, '(empty)'),
            ],
          ],
        ),
      ),
    );
  }

  /// Shelf's `Request.url` has no leading slash and is empty for the root
  /// path, so a bare `GET /` would otherwise render as blank.
  String _displayPath(String url) => url.isEmpty ? '/' : (url.startsWith('/') ? url : '/$url');

  String _deviceLabel(RequestLog log) {
    final ua = log.headers['user-agent'] ?? log.headers['User-Agent'];
    if (ua == null || ua.isEmpty) return 'Client';
    if (ua.contains('iPhone')) return 'iPhone';
    if (ua.contains('iPad')) return 'iPad';
    if (ua.contains('Android')) return 'Android';
    if (ua.contains('Macintosh')) return 'Mac';
    if (ua.contains('Windows')) return 'Windows';
    if (ua.contains('curl')) return 'curl';
    if (ua.contains('PostmanRuntime')) return 'Postman';
    return 'Client';
  }

  Widget _deviceChip(ArbTokens t, RequestLog log) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📍', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 7),
          Text(_deviceLabel(log), style: t.sans(size: 11.5, weight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(log.ip ?? '', style: t.mono(size: 11, color: t.textMuted)),
        ],
      ),
    );
  }

  Widget _plainBox(ArbTokens t, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(t.radius - 1),
        ),
        child: Text(text, style: t.mono(size: 12, color: t.textPrimary)),
      );

  Widget _methodChip(ArbTokens t, String method) {
    final color = t.methodColor(method);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(method, style: t.mono(size: 11, weight: FontWeight.w700, color: color)),
    );
  }

  Widget _statusChip(ArbTokens t, int code) {
    final color = t.statusColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text('$code', style: t.mono(size: 11, weight: FontWeight.w700, color: color)),
    );
  }
}

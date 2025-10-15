import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/request_log.dart';

class RealtimeLogTerminal extends StatelessWidget {
  final List<RequestLog> logs;
  final VoidCallback onViewAll;

  const RealtimeLogTerminal({
    super.key,
    required this.logs,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1E1E),
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildLogsList(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade800,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.terminal,
            color: Colors.green.shade400,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Text(
            'Recent Activity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.green.shade400,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.shade400.withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: logs.isEmpty
          ? _buildEmptyState()
          : Column(
        children: logs.map((log) => _buildLogEntry(log)).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 12),
          Text(
            'No logs yet',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start the server to see activity',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(RequestLog log) {
    final timeFormat = DateFormat('HH:mm:ss');
    final time = timeFormat.format(log.timestamp);
    final statusColor = _getStatusColor(log.statusCode);
    final methodColor = _getMethodColor(log.method);

    // Extract endpoint name from URL
    final endpoint = _extractEndpoint(log.url);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time
          Text(
            '[$time]',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Method
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: methodColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: methodColor.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Text(
              log.method.name.toUpperCase(),
              style: TextStyle(
                color: methodColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Endpoint
          Expanded(
            child: Text(
              endpoint,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Arrow
          Text(
            '→',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Status Code
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: statusColor,
                width: 1,
              ),
            ),
            child: Text(
              log.statusCode.toString(),
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade800,
            width: 1,
          ),
        ),
      ),
      child: TextButton.icon(
        onPressed: onViewAll,
        icon: const Icon(
          Icons.open_in_full,
          size: 16,
          color: Colors.green,
        ),
        label: const Text(
          'View All Logs',
          style: TextStyle(
            color: Colors.green,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }

  String _extractEndpoint(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.path.isEmpty ? '/' : uri.path;
    } catch (e) {
      return url;
    }
  }

  Color _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return Colors.green.shade400;
    } else if (statusCode >= 300 && statusCode < 400) {
      return Colors.blue.shade400;
    } else if (statusCode >= 400 && statusCode < 500) {
      return Colors.orange.shade400;
    } else {
      return Colors.red.shade400;
    }
  }

  Color _getMethodColor(RequestMethod method) {
    switch (method) {
      case RequestMethod.get:
        return Colors.blue.shade400;
      case RequestMethod.post:
        return Colors.green.shade400;
      case RequestMethod.put:
        return Colors.orange.shade400;
      case RequestMethod.delete:
        return Colors.red.shade400;
      case RequestMethod.patch:
        return Colors.purple.shade400;
      case RequestMethod.head:
        return Colors.cyan.shade400;
      case RequestMethod.options:
        return Colors.yellow.shade700;
    }
  }
}
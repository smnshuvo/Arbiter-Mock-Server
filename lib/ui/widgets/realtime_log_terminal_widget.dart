import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/request_log.dart';

class RealtimeLogTerminal extends StatelessWidget {
  final List<RequestLog> logs;

  const RealtimeLogTerminal({
    super.key,
    required this.logs,
  });

  @override
  Widget build(BuildContext context) {
    // Take only the last 3 logs
    final recentLogs = logs.length > 3
        ? logs.sublist(logs.length - 3)
        : logs;

    return Card(
      elevation: 4,
      color: const Color(0xFF1E1E1E), // Dark terminal background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.terminal,
                  color: Colors.greenAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Real-time Logs',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                    fontFamily: 'Courier',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Latest ${recentLogs.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.greenAccent,
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 100,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: recentLogs.isEmpty
                  ? const Center(
                child: Text(
                  'Waiting for requests...',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontFamily: 'Courier',
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
                  : ListView.builder(
                reverse: false,
                itemCount: recentLogs.length,
                itemBuilder: (context, index) {
                  return _buildLogEntry(recentLogs[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogEntry(RequestLog log) {
    final timeFormat = DateFormat('HH:mm:ss');
    final time = timeFormat.format(log.timestamp);
    final method = log.method.toString().split('.').last.toUpperCase();
    final statusCode = log.statusCode;
    final url = _truncateUrl(log.url);

    // Determine color based on status code
    Color statusColor;
    if (statusCode >= 200 && statusCode < 300) {
      statusColor = Colors.greenAccent;
    } else if (statusCode >= 400 && statusCode < 500) {
      statusColor = Colors.orangeAccent;
    } else if (statusCode >= 500) {
      statusColor = Colors.redAccent;
    } else {
      statusColor = Colors.blueAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 11,
            fontFamily: 'Courier',
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '[$time] ',
              style: const TextStyle(color: Colors.cyan),
            ),
            TextSpan(
              text: '$method ',
              style: TextStyle(
                color: _getMethodColor(method),
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: url,
              style: const TextStyle(color: Colors.white70),
            ),
            const TextSpan(
              text: ' → ',
              style: TextStyle(color: Colors.grey),
            ),
            TextSpan(
              text: statusCode.toString(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getMethodColor(String method) {
    switch (method) {
      case 'GET':
        return Colors.blue;
      case 'POST':
        return Colors.green;
      case 'PUT':
        return Colors.orange;
      case 'DELETE':
        return Colors.red;
      case 'PATCH':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _truncateUrl(String url) {
    // Remove query parameters for cleaner display
    final urlWithoutQuery = url.split('?').first;

    // If URL is too long, truncate it
    if (urlWithoutQuery.length > 35) {
      return '${urlWithoutQuery.substring(0, 32)}...';
    }
    return urlWithoutQuery;
  }
}
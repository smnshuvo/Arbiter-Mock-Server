import 'dart:convert';
import 'package:flutter/material.dart';

class JsonViewerWidget extends StatefulWidget {
  final String jsonString;
  final int initialExpandDepth;

  const JsonViewerWidget({
    super.key,
    required this.jsonString,
    this.initialExpandDepth = 1,
  });

  @override
  State<JsonViewerWidget> createState() => _JsonViewerWidgetState();
}

class _JsonViewerWidgetState extends State<JsonViewerWidget> {
  dynamic _jsonData;
  bool _isValidJson = true;
  final Map<String, bool> _expandedNodes = {};

  @override
  void initState() {
    super.initState();
    _parseJson();
  }

  void _parseJson() {
    try {
      _jsonData = json.decode(widget.jsonString);
      _isValidJson = true;
      _initializeExpandedNodes(_jsonData, '', 0);
    } catch (e) {
      _isValidJson = false;
    }
  }

  void _initializeExpandedNodes(dynamic data, String path, int depth) {
    if (data is Map) {
      _expandedNodes[path] = depth < widget.initialExpandDepth;
      data.forEach((key, value) {
        _initializeExpandedNodes(value, '$path.$key', depth + 1);
      });
    } else if (data is List) {
      _expandedNodes[path] = depth < widget.initialExpandDepth;
      for (int i = 0; i < data.length; i++) {
        _initializeExpandedNodes(data[i], '$path[$i]', depth + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isValidJson) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: SelectableText(
          widget.jsonString,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText.rich(
          TextSpan(
            children: _buildJsonTree(_jsonData, '', 0),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _buildJsonTree(dynamic data, String path, int indent) {
    List<InlineSpan> spans = [];

    if (data is Map) {
      spans.addAll(_buildMapTree(data, path, indent));
    } else if (data is List) {
      spans.addAll(_buildListTree(data, path, indent));
    } else {
      spans.add(_buildValueSpan(data));
    }

    return spans;
  }

  List<InlineSpan> _buildMapTree(Map data, String path, int indent) {
    List<InlineSpan> spans = [];
    final isExpanded = _expandedNodes[path] ?? false;

    if (data.isEmpty) {
      spans.add(const TextSpan(
        text: '{}',
        style: TextStyle(color: Colors.grey),
      ));
      return spans;
    }

    // Opening brace with expand/collapse
    spans.add(WidgetSpan(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _expandedNodes[path] = !isExpanded;
          });
        },
        child: Icon(
          isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
          size: 16,
          color: Colors.blue[700],
        ),
      ),
    ));
    spans.add(TextSpan(
      text: '{',
      style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold),
    ));

    if (isExpanded) {
      spans.add(const TextSpan(text: '\n'));

      final entries = data.entries.toList();
      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final isLast = i == entries.length - 1;

        // Indentation
        spans.add(TextSpan(text: '  ' * (indent + 1)));

        // Key
        spans.add(TextSpan(
          text: '"${entry.key}"',
          style: const TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ));
        spans.add(const TextSpan(text: ': '));

        // Value
        final childPath = '$path.${entry.key}';
        if (entry.value is Map || entry.value is List) {
          spans.addAll(_buildJsonTree(entry.value, childPath, indent + 1));
        } else {
          spans.add(_buildValueSpan(entry.value));
        }

        if (!isLast) {
          spans.add(const TextSpan(text: ','));
        }
        spans.add(const TextSpan(text: '\n'));
      }

      // Closing brace
      spans.add(TextSpan(text: '  ' * indent));
    } else {
      spans.add(TextSpan(
        text: ' ... ',
        style: TextStyle(color: Colors.grey[600]),
      ));
    }

    spans.add(TextSpan(
      text: '}',
      style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold),
    ));

    return spans;
  }

  List<InlineSpan> _buildListTree(List data, String path, int indent) {
    List<InlineSpan> spans = [];
    final isExpanded = _expandedNodes[path] ?? false;

    if (data.isEmpty) {
      spans.add(const TextSpan(
        text: '[]',
        style: TextStyle(color: Colors.grey),
      ));
      return spans;
    }

    // Opening bracket with expand/collapse
    spans.add(WidgetSpan(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _expandedNodes[path] = !isExpanded;
          });
        },
        child: Icon(
          isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
          size: 16,
          color: Colors.blue[700],
        ),
      ),
    ));
    spans.add(TextSpan(
      text: '[',
      style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold),
    ));

    if (isExpanded) {
      spans.add(const TextSpan(text: '\n'));

      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        final isLast = i == data.length - 1;

        // Indentation
        spans.add(TextSpan(text: '  ' * (indent + 1)));

        // Value
        final childPath = '$path[$i]';
        if (item is Map || item is List) {
          spans.addAll(_buildJsonTree(item, childPath, indent + 1));
        } else {
          spans.add(_buildValueSpan(item));
        }

        if (!isLast) {
          spans.add(const TextSpan(text: ','));
        }
        spans.add(const TextSpan(text: '\n'));
      }

      // Closing bracket
      spans.add(TextSpan(text: '  ' * indent));
    } else {
      spans.add(TextSpan(
        text: ' ... ',
        style: TextStyle(color: Colors.grey[600]),
      ));
    }

    spans.add(TextSpan(
      text: ']',
      style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold),
    ));

    return spans;
  }

  TextSpan _buildValueSpan(dynamic value) {
    if (value == null) {
      return const TextSpan(
        text: 'null',
        style: TextStyle(
          color: Colors.red,
          fontStyle: FontStyle.italic,
        ),
      );
    } else if (value is String) {
      return TextSpan(
        text: '"$value"',
        style: const TextStyle(color: Colors.green),
      );
    } else if (value is num) {
      return TextSpan(
        text: value.toString(),
        style: const TextStyle(color: Colors.orange),
      );
    } else if (value is bool) {
      return TextSpan(
        text: value.toString(),
        style: const TextStyle(
          color: Colors.purple,
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      return TextSpan(
        text: value.toString(),
        style: const TextStyle(color: Colors.black87),
      );
    }
  }
}
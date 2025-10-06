import 'package:flutter/material.dart';
import '../../domain/entities/request_log.dart';
import '../../domain/repositories/log_repository.dart';

class LogFilterScreen extends StatefulWidget {
  final LogFilter? currentFilter;

  const LogFilterScreen({Key? key, this.currentFilter}) : super(key: key);

  @override
  State<LogFilterScreen> createState() => _LogFilterScreenState();
}

class _LogFilterScreenState extends State<LogFilterScreen> {
  late Set<RequestMethod> _selectedMethods;
  late Set<int> _selectedStatusCodes;
  late Set<LogType> _selectedLogTypes;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedMethods = widget.currentFilter?.methods?.toSet() ?? {};
    _selectedStatusCodes = widget.currentFilter?.statusCodes?.toSet() ?? {};
    _selectedLogTypes = widget.currentFilter?.logTypes?.toSet() ?? {};
    _startDate = widget.currentFilter?.startDate;
    _endDate = widget.currentFilter?.endDate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Filter Logs'),
        actions: [
          TextButton(
            onPressed: _clearAll,
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _applyFilter,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMethodsSection(),
          const SizedBox(height: 24),
          _buildStatusCodesSection(),
          const SizedBox(height: 24),
          _buildLogTypesSection(),
          const SizedBox(height: 24),
          _buildDateRangeSection(),
        ],
      ),
    );
  }

  Widget _buildMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HTTP Methods',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: RequestMethod.values.map((method) {
            final isSelected = _selectedMethods.contains(method);
            return FilterChip(
              label: Text(method.name.toUpperCase()),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedMethods.add(method);
                  } else {
                    _selectedMethods.remove(method);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStatusCodesSection() {
    final statusCodeGroups = [
      {'label': '2xx Success', 'codes': [200, 201, 204]},
      {'label': '3xx Redirect', 'codes': [301, 302, 304]},
      {'label': '4xx Client Error', 'codes': [400, 401, 403, 404]},
      {'label': '5xx Server Error', 'codes': [500, 502, 503]},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status Codes',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...statusCodeGroups.map((group) {
          final codes = group['codes'] as List<int>;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group['label'] as String,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: codes.map((code) {
                  final isSelected = _selectedStatusCodes.contains(code);
                  return FilterChip(
                    label: Text(code.toString()),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedStatusCodes.add(code);
                        } else {
                          _selectedStatusCodes.remove(code);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildLogTypesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Log Types',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: LogType.values.map((type) {
            final isSelected = _selectedLogTypes.contains(type);
            return FilterChip(
              label: Text(type == LogType.mock ? 'Mock' : 'Pass-through'),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedLogTypes.add(type);
                  } else {
                    _selectedLogTypes.remove(type);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDateRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date Range',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ListTile(
          title: const Text('Start Date'),
          subtitle: Text(_startDate?.toString().split(' ').first ?? 'Not set'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _startDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              setState(() {
                _startDate = date;
              });
            }
          },
        ),
        ListTile(
          title: const Text('End Date'),
          subtitle: Text(_endDate?.toString().split(' ').first ?? 'Not set'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _endDate ?? DateTime.now(),
              firstDate: _startDate ?? DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              setState(() {
                _endDate = date;
              });
            }
          },
        ),
        if (_startDate != null || _endDate != null)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: TextButton(
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
              },
              child: const Text('Clear Date Range'),
            ),
          ),
      ],
    );
  }

  void _clearAll() {
    setState(() {
      _selectedMethods.clear();
      _selectedStatusCodes.clear();
      _selectedLogTypes.clear();
      _startDate = null;
      _endDate = null;
    });
  }

  void _applyFilter() {
    final filter = LogFilter(
      methods: _selectedMethods.isEmpty ? null : _selectedMethods.toList(),
      statusCodes: _selectedStatusCodes.isEmpty ? null : _selectedStatusCodes.toList(),
      logTypes: _selectedLogTypes.isEmpty ? null : _selectedLogTypes.toList(),
      startDate: _startDate,
      endDate: _endDate,
    );

    Navigator.pop(context, filter);
  }
}
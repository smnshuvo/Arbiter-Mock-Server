import 'package:flutter/material.dart';
import '../../domain/entities/endpoint.dart';

class ConditionalMockScreen extends StatefulWidget {
  final List<ConditionalMock> conditionalMocks;

  const ConditionalMockScreen({
    Key? key,
    required this.conditionalMocks,
  }) : super(key: key);

  @override
  State<ConditionalMockScreen> createState() => _ConditionalMockScreenState();
}

class _ConditionalMockScreenState extends State<ConditionalMockScreen> {
  late List<ConditionalMock> _conditionalMocks;

  @override
  void initState() {
    super.initState();
    _conditionalMocks = List.from(widget.conditionalMocks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conditional Mocks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              Navigator.pop(context, _conditionalMocks);
            },
          ),
        ],
      ),
      body: _conditionalMocks.isEmpty
          ? _buildEmptyState()
          : _buildList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addConditionalMock,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rule,
            size: 100,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No conditional mocks configured',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add a conditional mock',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _conditionalMocks.length,
      itemBuilder: (context, index) {
        final mock = _conditionalMocks[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            leading: Icon(
              mock.type == ConditionalMatchType.queryParam
                  ? Icons.link
                  : Icons.data_object,
              color: Colors.blue,
            ),
            title: Text(
              '${mock.fieldName} = ${mock.fieldValue}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              mock.type == ConditionalMatchType.queryParam
                  ? 'Query Parameter'
                  : 'Body Field',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                setState(() {
                  _conditionalMocks.removeAt(index);
                });
              },
            ),
            onTap: () => _editConditionalMock(index),
          ),
        );
      },
    );
  }

  void _addConditionalMock() async {
    final result = await _showConditionalMockDialog(null);
    if (result != null) {
      setState(() {
        _conditionalMocks.add(result);
      });
    }
  }

  void _editConditionalMock(int index) async {
    final result = await _showConditionalMockDialog(_conditionalMocks[index]);
    if (result != null) {
      setState(() {
        _conditionalMocks[index] = result;
      });
    }
  }

  Future<ConditionalMock?> _showConditionalMockDialog(
      ConditionalMock? existing,
      ) async {
    final typeController = TextEditingController();
    final fieldNameController = TextEditingController(
      text: existing?.fieldName ?? '',
    );
    final fieldValueController = TextEditingController(
      text: existing?.fieldValue ?? '',
    );
    final mockResponseController = TextEditingController(
      text: existing?.mockResponse ?? '{}',
    );

    ConditionalMatchType selectedType =
        existing?.type ?? ConditionalMatchType.queryParam;

    return await showDialog<ConditionalMock>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Conditional Mock' : 'Edit Conditional Mock'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<ConditionalMatchType>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Match Type',
                        border: OutlineInputBorder(),
                      ),
                      items: ConditionalMatchType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(
                            type == ConditionalMatchType.queryParam
                                ? 'Query Parameter'
                                : 'Body Field',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedType = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: fieldNameController,
                      decoration: InputDecoration(
                        labelText: selectedType == ConditionalMatchType.queryParam
                            ? 'Query Parameter Name'
                            : 'Body Field Name',
                        hintText: selectedType == ConditionalMatchType.queryParam
                            ? 'id'
                            : 'userId',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: fieldValueController,
                      decoration: const InputDecoration(
                        labelText: 'Field Value',
                        hintText: '1',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: mockResponseController,
                      decoration: const InputDecoration(
                        labelText: 'Mock Response (JSON)',
                        hintText: '{"message": "Success"}',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 6,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (fieldNameController.text.isNotEmpty &&
                        fieldValueController.text.isNotEmpty &&
                        mockResponseController.text.isNotEmpty) {
                      final conditionalMock = ConditionalMock(
                        type: selectedType,
                        fieldName: fieldNameController.text,
                        fieldValue: fieldValueController.text,
                        mockResponse: mockResponseController.text,
                      );
                      Navigator.pop(dialogContext, conditionalMock);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
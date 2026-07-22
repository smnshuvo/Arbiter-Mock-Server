import 'package:flutter/material.dart';

/// "Creates a mock server with N endpoint(s) from the selected requests."
/// Shared by the mobile logs screen and the wide-layout logs pane — both
/// bulk-select captured requests and spin up a new [Profile] from them.
class NewCollectionDialog extends StatefulWidget {
  final int count;

  const NewCollectionDialog({super.key, required this.count});

  @override
  State<NewCollectionDialog> createState() => _NewCollectionDialogState();
}

class _NewCollectionDialogState extends State<NewCollectionDialog> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New collection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Creates a mock server with ${widget.count} endpoint'
            '${widget.count == 1 ? '' : 's'} from the selected requests.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Collection name',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _nameController.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

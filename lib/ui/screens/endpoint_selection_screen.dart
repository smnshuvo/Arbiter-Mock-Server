import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/endpoint.dart';
import '../bloc/endpoint/endpoint_bloc.dart';

class EndpointSelectionScreen extends StatefulWidget {
  final List<String> selectedEndpointIds;

  const EndpointSelectionScreen({
    Key? key,
    required this.selectedEndpointIds,
  }) : super(key: key);

  @override
  State<EndpointSelectionScreen> createState() =>
      _EndpointSelectionScreenState();
}

class _EndpointSelectionScreenState extends State<EndpointSelectionScreen> {
  late Set<String> _selectedIds;
  List<Endpoint> _allEndpoints = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedEndpointIds);
    context.read<EndpointBloc>().add(LoadEndpointsEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Endpoints'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            onPressed: _selectAll,
            tooltip: 'Select All',
          ),
          IconButton(
            icon: const Icon(Icons.deselect),
            onPressed: _deselectAll,
            tooltip: 'Deselect All',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSelectionSummary(),
          Expanded(
            child: BlocBuilder<EndpointBloc, EndpointState>(
              builder: (context, state) {
                if (state is EndpointLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is EndpointLoaded) {
                  _allEndpoints = state.endpoints;
                  final filteredEndpoints = _filterEndpoints(state.endpoints);

                  if (filteredEndpoints.isEmpty) {
                    return _buildEmptyState();
                  }

                  return _buildEndpointList(filteredEndpoints);
                }

                return const SizedBox();
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search endpoints...',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
            },
          )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildSelectionSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.withOpacity(0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_selectedIds.length} endpoint(s) selected',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (_selectedIds.isNotEmpty)
            TextButton(
              onPressed: _deselectAll,
              child: const Text('Clear Selection'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No endpoints found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointList(List<Endpoint> endpoints) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        final isSelected = _selectedIds.contains(endpoint.id);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedIds.add(endpoint.id);
                } else {
                  _selectedIds.remove(endpoint.id);
                }
              });
            },
            title: Text(
              endpoint.pattern,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Row(
              children: [
                _buildChip(
                  endpoint.mode == EndpointMode.mock ? 'Mock' : 'Pass-through',
                  endpoint.mode == EndpointMode.mock
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                _buildChip(
                  endpoint.matchType.name.toUpperCase(),
                  Colors.blue,
                ),
                const SizedBox(width: 8),
                if (!endpoint.isEnabled)
                  _buildChip('Disabled', Colors.grey),
              ],
            ),
            secondary: Icon(
              endpoint.mode == EndpointMode.mock ? Icons.code : Icons.swap_horiz,
              color: endpoint.isEnabled ? Colors.blue : Colors.grey,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, _selectedIds.toList());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: Text(
                  'Save (${_selectedIds.length})',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Endpoint> _filterEndpoints(List<Endpoint> endpoints) {
    if (_searchQuery.isEmpty) {
      return endpoints;
    }

    return endpoints.where((endpoint) {
      return endpoint.pattern
          .toLowerCase()
          .contains(_searchQuery.toLowerCase()) ||
          endpoint.mode.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  void _selectAll() {
    setState(() {
      _selectedIds = Set.from(_allEndpoints.map((e) => e.id));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedIds.clear();
    });
  }
}
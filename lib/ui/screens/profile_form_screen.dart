import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/profile.dart';
import '../bloc/profile/profile_bloc.dart';

class ProfileFormScreen extends StatefulWidget {
  final Profile? profile;

  const ProfileFormScreen({Key? key, this.profile}) : super(key: key);

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _portController;
  late TextEditingController _passThroughUrlController;

  late bool _autoPassThrough;
  late bool _passThroughAll;
  late bool _useDeviceIp;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.profile?.name ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.profile?.description ?? '',
    );
    _portController = TextEditingController(
      text: widget.profile?.port.toString() ?? '8080',
    );
    _passThroughUrlController = TextEditingController(
      text: widget.profile?.settings.globalPassThroughUrl ?? '',
    );

    _autoPassThrough = widget.profile?.settings.autoPassThrough ?? false;
    _passThroughAll = widget.profile?.settings.passThroughAll ?? false;
    _useDeviceIp = widget.profile?.settings.useDeviceIp ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _portController.dispose();
    _passThroughUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'Create Profile' : 'Edit Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveProfile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Basic Information Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Basic Information',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Profile Name *',
                          hintText: 'e.g., Development, Testing, Production',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.label),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a profile name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Optional description',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: 'Port *',
                          hintText: '8080',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.router),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a port';
                          }
                          final port = int.tryParse(value);
                          if (port == null || port < 1024 || port > 65535) {
                            return 'Port must be between 1024 and 65535';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Server Settings Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Server Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Use Device IP'),
                        subtitle: const Text(
                          'Allow other devices to connect to this server',
                        ),
                        value: _useDeviceIp,
                        onChanged: (value) {
                          setState(() {
                            _useDeviceIp = value;
                          });
                        },
                        secondary: const Icon(Icons.wifi),
                      ),
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Auto Pass-Through'),
                        subtitle: const Text(
                          'Forward unmatched requests to a base URL',
                        ),
                        value: _autoPassThrough,
                        onChanged: (value) {
                          setState(() {
                            _autoPassThrough = value;
                          });
                        },
                        secondary: const Icon(Icons.swap_horiz),
                      ),
                      if (_autoPassThrough) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passThroughUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Global Pass-Through URL',
                            hintText: 'https://api.example.com',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.link),
                            helperText:
                            'Unmatched requests will be forwarded here',
                          ),
                          validator: (value) {
                            if (_autoPassThrough &&
                                (value == null || value.isEmpty)) {
                              return 'Please enter a pass-through URL';
                            }
                            if (value != null &&
                                value.isNotEmpty &&
                                !value.startsWith('http')) {
                              return 'URL must start with http:// or https://';
                            }
                            return null;
                          },
                        ),
                      ],
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Pass Through All'),
                        subtitle: const Text(
                          'Forward all requests (ignore endpoint matches)',
                        ),
                        value: _passThroughAll,
                        onChanged: (value) {
                          setState(() {
                            _passThroughAll = value;
                          });
                        },
                        secondary: const Icon(Icons.all_inclusive),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Save Button
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save, color: Colors.white),
                label: Text(
                  widget.profile == null ? 'Create Profile' : 'Update Profile',
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      final now = DateTime.now();
      final profile = Profile(
        id: widget.profile?.id ?? now.millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        description: _descriptionController.text,
        port: int.parse(_portController.text),
        isActive: widget.profile?.isActive ?? false,
        endpointIds: widget.profile?.endpointIds ?? [],
        createdAt: widget.profile?.createdAt ?? now,
        updatedAt: now,
        settings: ProfileSettings(
          globalPassThroughUrl:
          _autoPassThrough ? _passThroughUrlController.text : null,
          autoPassThrough: _autoPassThrough,
          passThroughAll: _passThroughAll,
          useDeviceIp: _useDeviceIp,
        ),
      );

      if (widget.profile == null) {
        context.read<ProfileBloc>().add(CreateProfileEvent(profile));
      } else {
        context.read<ProfileBloc>().add(UpdateProfileEvent(profile));
      }

      Navigator.pop(context);
    }
  }
}
import 'package:equatable/equatable.dart';

class Profile extends Equatable {
  final String id;
  final String name;
  final String description;
  final int port;
  final bool isActive;
  final List<String> endpointIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProfileSettings settings;

  const Profile({
    required this.id,
    required this.name,
    required this.description,
    required this.port,
    required this.isActive,
    required this.endpointIds,
    required this.createdAt,
    required this.updatedAt,
    required this.settings,
  });

  Profile copyWith({
    String? id,
    String? name,
    String? description,
    int? port,
    bool? isActive,
    List<String>? endpointIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProfileSettings? settings,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      port: port ?? this.port,
      isActive: isActive ?? this.isActive,
      endpointIds: endpointIds ?? this.endpointIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      settings: settings ?? this.settings,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    port,
    isActive,
    endpointIds,
    createdAt,
    updatedAt,
    settings,
  ];
}

class ProfileSettings extends Equatable {
  final String? globalPassThroughUrl;
  final bool autoPassThrough;
  final bool passThroughAll;
  final bool useDeviceIp;

  const ProfileSettings({
    this.globalPassThroughUrl,
    this.autoPassThrough = false,
    this.passThroughAll = false,
    this.useDeviceIp = false,
  });

  ProfileSettings copyWith({
    String? globalPassThroughUrl,
    bool? autoPassThrough,
    bool? passThroughAll,
    bool? useDeviceIp,
  }) {
    return ProfileSettings(
      globalPassThroughUrl: globalPassThroughUrl ?? this.globalPassThroughUrl,
      autoPassThrough: autoPassThrough ?? this.autoPassThrough,
      passThroughAll: passThroughAll ?? this.passThroughAll,
      useDeviceIp: useDeviceIp ?? this.useDeviceIp,
    );
  }

  @override
  List<Object?> get props => [
    globalPassThroughUrl,
    autoPassThrough,
    passThroughAll,
    useDeviceIp,
  ];
}
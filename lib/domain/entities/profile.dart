import 'package:equatable/equatable.dart';

enum ServerType { http, ftp }

class ProfileSettings extends Equatable {
  final String? globalPassThroughUrl;
  final bool autoPassThrough;
  final bool useDeviceIp;

  const ProfileSettings({
    this.globalPassThroughUrl,
    this.autoPassThrough = false,
    this.useDeviceIp = false,
  });

  ProfileSettings copyWith({
    String? globalPassThroughUrl,
    bool? autoPassThrough,
    bool? useDeviceIp,
    bool clearPassThroughUrl = false,
  }) {
    return ProfileSettings(
      globalPassThroughUrl: clearPassThroughUrl ? null : (globalPassThroughUrl ?? this.globalPassThroughUrl),
      autoPassThrough: autoPassThrough ?? this.autoPassThrough,
      useDeviceIp: useDeviceIp ?? this.useDeviceIp,
    );
  }

  @override
  List<Object?> get props => [globalPassThroughUrl, autoPassThrough, useDeviceIp];
}

class Profile extends Equatable {
  final String id;
  final String name;
  final String? description;
  final int port;
  final ServerType type;
  final ProfileSettings settings;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    required this.name,
    this.description,
    this.port = 8080,
    this.type = ServerType.http,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
  });

  Profile copyWith({
    String? id,
    String? name,
    String? description,
    int? port,
    ServerType? type,
    ProfileSettings? settings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Profile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      port: port ?? this.port,
      type: type ?? this.type,
      settings: settings ?? this.settings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, description, port, type, settings, createdAt, updatedAt];
}

import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/profile.dart';

part 'profile_model.g.dart';

@JsonSerializable()
class ProfileSettingsModel {
  final String? globalPassThroughUrl;
  final bool autoPassThrough;
  final bool passThroughAll;
  final bool useDeviceIp;

  ProfileSettingsModel({
    this.globalPassThroughUrl,
    required this.autoPassThrough,
    required this.passThroughAll,
    required this.useDeviceIp,
  });

  factory ProfileSettingsModel.fromJson(Map<String, dynamic> json) =>
      _$ProfileSettingsModelFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileSettingsModelToJson(this);

  factory ProfileSettingsModel.fromEntity(ProfileSettings settings) {
    return ProfileSettingsModel(
      globalPassThroughUrl: settings.globalPassThroughUrl,
      autoPassThrough: settings.autoPassThrough,
      passThroughAll: false,
      useDeviceIp: settings.useDeviceIp,
    );
  }

  ProfileSettings toEntity() {
    return ProfileSettings(
      globalPassThroughUrl: globalPassThroughUrl,
      autoPassThrough: autoPassThrough,
      useDeviceIp: useDeviceIp,
    );
  }
}

@JsonSerializable()
class ProfileModel {
  final String id;
  final String name;
  final String description;
  final int port;
  final String type;
  final int isActive;
  final String settings;
  final String createdAt;
  final String updatedAt;

  ProfileModel({
    required this.id,
    required this.name,
    required this.description,
    required this.port,
    this.type = 'http',
    required this.isActive,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) =>
      _$ProfileModelFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileModelToJson(this);

  factory ProfileModel.fromEntity(Profile profile) {
    final settingsModel = ProfileSettingsModel.fromEntity(profile.settings);
    return ProfileModel(
      id: profile.id,
      name: profile.name,
      description: profile.description ?? '',
      port: profile.port,
      type: profile.type.name,
      isActive: 0,
      settings: jsonEncode(settingsModel.toJson()),
      createdAt: profile.createdAt.toIso8601String(),
      updatedAt: profile.updatedAt.toIso8601String(),
    );
  }

  Profile toEntity() {
    ProfileSettings profileSettings = const ProfileSettings();
    try {
      final settingsJson = jsonDecode(settings) as Map<String, dynamic>;
      profileSettings = ProfileSettingsModel.fromJson(settingsJson).toEntity();
    } catch (_) {}

    return Profile(
      id: id,
      name: name,
      description: description.isEmpty ? null : description,
      port: port,
      type: ServerType.values.firstWhere(
        (t) => t.name == type,
        orElse: () => ServerType.http,
      ),
      settings: profileSettings,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'port': port,
      'type': type,
      'settings': settings,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'],
      name: map['name'],
      description: map['description'] ?? '',
      port: map['port'] ?? 8080,
      type: map['type'] ?? 'http',
      isActive: map['isActive'] ?? 0,
      settings: map['settings'] ?? '{}',
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
    );
  }
}

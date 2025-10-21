import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/profile.dart';

part 'profile_model.g.dart';

@JsonSerializable()
class ProfileModel {
  final String id;
  final String name;
  final String description;
  final int port;
  final int isActive; // SQLite doesn't have boolean, using int (0 or 1)
  final String settings; // JSON string of ProfileSettings
  final String createdAt;
  final String updatedAt;

  ProfileModel({
    required this.id,
    required this.name,
    required this.description,
    required this.port,
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
      description: profile.description,
      port: profile.port,
      isActive: profile.isActive ? 1 : 0,
      settings: jsonEncode(settingsModel.toMap()),
      createdAt: profile.createdAt.toIso8601String(),
      updatedAt: profile.updatedAt.toIso8601String(),
    );
  }

  Profile toEntity(List<String> endpointIds) {
    final settingsMap = jsonDecode(settings) as Map<String, dynamic>;
    final settingsModel = ProfileSettingsModel.fromMap(settingsMap);

    return Profile(
      id: id,
      name: name,
      description: description,
      port: port,
      isActive: isActive == 1,
      endpointIds: endpointIds,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      settings: settingsModel.toEntity(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'port': port,
      'isActive': isActive,
      'settings': settings,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      port: map['port'],
      isActive: map['isActive'],
      settings: map['settings'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
    );
  }
}

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
      passThroughAll: settings.passThroughAll,
      useDeviceIp: settings.useDeviceIp,
    );
  }

  ProfileSettings toEntity() {
    return ProfileSettings(
      globalPassThroughUrl: globalPassThroughUrl,
      autoPassThrough: autoPassThrough,
      passThroughAll: passThroughAll,
      useDeviceIp: useDeviceIp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'globalPassThroughUrl': globalPassThroughUrl,
      'autoPassThrough': autoPassThrough,
      'passThroughAll': passThroughAll,
      'useDeviceIp': useDeviceIp,
    };
  }

  factory ProfileSettingsModel.fromMap(Map<String, dynamic> map) {
    return ProfileSettingsModel(
      globalPassThroughUrl: map['globalPassThroughUrl'],
      autoPassThrough: map['autoPassThrough'] ?? false,
      passThroughAll: map['passThroughAll'] ?? false,
      useDeviceIp: map['useDeviceIp'] ?? false,
    );
  }
}
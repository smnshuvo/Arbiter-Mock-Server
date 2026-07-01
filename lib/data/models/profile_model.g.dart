// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileSettingsModel _$ProfileSettingsModelFromJson(
        Map<String, dynamic> json) =>
    ProfileSettingsModel(
      globalPassThroughUrl: json['globalPassThroughUrl'] as String?,
      autoPassThrough: json['autoPassThrough'] as bool,
      passThroughAll: json['passThroughAll'] as bool,
      useDeviceIp: json['useDeviceIp'] as bool,
    );

Map<String, dynamic> _$ProfileSettingsModelToJson(
        ProfileSettingsModel instance) =>
    <String, dynamic>{
      'globalPassThroughUrl': instance.globalPassThroughUrl,
      'autoPassThrough': instance.autoPassThrough,
      'passThroughAll': instance.passThroughAll,
      'useDeviceIp': instance.useDeviceIp,
    };

ProfileModel _$ProfileModelFromJson(Map<String, dynamic> json) => ProfileModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      port: (json['port'] as num).toInt(),
      type: json['type'] as String? ?? 'http',
      isActive: (json['isActive'] as num).toInt(),
      settings: json['settings'] as String,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );

Map<String, dynamic> _$ProfileModelToJson(ProfileModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'port': instance.port,
      'type': instance.type,
      'isActive': instance.isActive,
      'settings': instance.settings,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
    };

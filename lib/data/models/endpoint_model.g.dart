// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'endpoint_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EndpointModel _$EndpointModelFromJson(Map<String, dynamic> json) =>
    EndpointModel(
      id: json['id'] as String,
      pattern: json['pattern'] as String,
      matchType: json['matchType'] as String,
      mode: json['mode'] as String,
      mockResponse: json['mockResponse'] as String?,
      delayMs: (json['delayMs'] as num).toInt(),
      targetUrl: json['targetUrl'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      isEnabled: (json['isEnabled'] as num).toInt(),
      conditionalMocksJson: json['conditionalMocksJson'] as String?,
      useConditionalMock: (json['useConditionalMock'] as num).toInt(),
    );

Map<String, dynamic> _$EndpointModelToJson(EndpointModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'pattern': instance.pattern,
      'matchType': instance.matchType,
      'mode': instance.mode,
      'mockResponse': instance.mockResponse,
      'delayMs': instance.delayMs,
      'targetUrl': instance.targetUrl,
      'createdAt': instance.createdAt,
      'updatedAt': instance.updatedAt,
      'isEnabled': instance.isEnabled,
      'conditionalMocksJson': instance.conditionalMocksJson,
      'useConditionalMock': instance.useConditionalMock,
    };

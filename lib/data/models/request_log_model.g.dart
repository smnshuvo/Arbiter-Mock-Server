// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'request_log_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RequestLogModel _$RequestLogModelFromJson(Map<String, dynamic> json) =>
    RequestLogModel(
      id: json['id'] as String,
      timestamp: json['timestamp'] as String,
      method: json['method'] as String,
      url: json['url'] as String,
      headers: json['headers'] as String,
      requestBody: json['requestBody'] as String?,
      statusCode: (json['statusCode'] as num).toInt(),
      responseBody: json['responseBody'] as String?,
      responseTimeMs: (json['responseTimeMs'] as num).toInt(),
      logType: json['logType'] as String,
      matchedEndpointId: json['matchedEndpointId'] as String?,
      profileId: json['profileId'] as String?,
    );

Map<String, dynamic> _$RequestLogModelToJson(RequestLogModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'timestamp': instance.timestamp,
      'method': instance.method,
      'url': instance.url,
      'headers': instance.headers,
      'requestBody': instance.requestBody,
      'statusCode': instance.statusCode,
      'responseBody': instance.responseBody,
      'responseTimeMs': instance.responseTimeMs,
      'logType': instance.logType,
      'matchedEndpointId': instance.matchedEndpointId,
      'profileId': instance.profileId,
    };

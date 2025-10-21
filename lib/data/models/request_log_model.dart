import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/request_log.dart';

part 'request_log_model.g.dart';

@JsonSerializable()
class RequestLogModel {
  final String id;
  final String timestamp;
  final String method;
  final String url;
  final String headers;
  final String? requestBody;
  final int statusCode;
  final String? responseBody;
  final int responseTimeMs;
  final String logType;
  final String? matchedEndpointId;
  final String? profileId; // NEW - track which profile handled the request

  RequestLogModel({
    required this.id,
    required this.timestamp,
    required this.method,
    required this.url,
    required this.headers,
    this.requestBody,
    required this.statusCode,
    this.responseBody,
    required this.responseTimeMs,
    required this.logType,
    this.matchedEndpointId,
    this.profileId, // NEW
  });

  factory RequestLogModel.fromJson(Map<String, dynamic> json) =>
      _$RequestLogModelFromJson(json);

  Map<String, dynamic> toJson() => _$RequestLogModelToJson(this);

  factory RequestLogModel.fromEntity(RequestLog log) {
    return RequestLogModel(
      id: log.id,
      timestamp: log.timestamp.toIso8601String(),
      method: log.method.name,
      url: log.url,
      headers: jsonEncode(log.headers),
      requestBody: log.requestBody,
      statusCode: log.statusCode,
      responseBody: log.responseBody,
      responseTimeMs: log.responseTimeMs,
      logType: log.logType.name,
      matchedEndpointId: log.matchedEndpointId,
      profileId: log.profileId, // NEW
    );
  }

  RequestLog toEntity() {
    return RequestLog(
      id: id,
      timestamp: DateTime.parse(timestamp),
      method: RequestMethodExtension.fromString(method),
      url: url,
      headers: Map<String, String>.from(jsonDecode(headers)),
      requestBody: requestBody,
      statusCode: statusCode,
      responseBody: responseBody,
      responseTimeMs: responseTimeMs,
      logType: LogType.values.firstWhere(
            (e) => e.name == logType,
        orElse: () => LogType.mock,
      ),
      matchedEndpointId: matchedEndpointId,
      profileId: profileId, // NEW
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'method': method,
      'url': url,
      'headers': headers,
      'requestBody': requestBody,
      'statusCode': statusCode,
      'responseBody': responseBody,
      'responseTimeMs': responseTimeMs,
      'logType': logType,
      'matchedEndpointId': matchedEndpointId,
      'profileId': profileId, // NEW
    };
  }

  factory RequestLogModel.fromMap(Map<String, dynamic> map) {
    return RequestLogModel(
      id: map['id'],
      timestamp: map['timestamp'],
      method: map['method'],
      url: map['url'],
      headers: map['headers'],
      requestBody: map['requestBody'],
      statusCode: map['statusCode'],
      responseBody: map['responseBody'],
      responseTimeMs: map['responseTimeMs'],
      logType: map['logType'],
      matchedEndpointId: map['matchedEndpointId'],
      profileId: map['profileId'], // NEW
    );
  }
}
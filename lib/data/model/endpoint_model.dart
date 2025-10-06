import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/endpoint.dart';

part 'endpoint_model.g.dart';

@JsonSerializable()
class EndpointModel {
  final String id;
  final String pattern;
  final String matchType;
  final String mode;
  final String? mockResponse;
  final int delayMs;
  final String? targetUrl;
  final String createdAt;
  final String updatedAt;
  final int isEnabled;

  EndpointModel({
    required this.id,
    required this.pattern,
    required this.matchType,
    required this.mode,
    this.mockResponse,
    required this.delayMs,
    this.targetUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.isEnabled,
  });

  factory EndpointModel.fromJson(Map<String, dynamic> json) =>
      _$EndpointModelFromJson(json);

  Map<String, dynamic> toJson() => _$EndpointModelToJson(this);

  factory EndpointModel.fromEntity(Endpoint endpoint) {
    return EndpointModel(
      id: endpoint.id,
      pattern: endpoint.pattern,
      matchType: endpoint.matchType.name,
      mode: endpoint.mode.name,
      mockResponse: endpoint.mockResponse,
      delayMs: endpoint.delayMs,
      targetUrl: endpoint.targetUrl,
      createdAt: endpoint.createdAt.toIso8601String(),
      updatedAt: endpoint.updatedAt.toIso8601String(),
      isEnabled: endpoint.isEnabled ? 1 : 0,
    );
  }

  Endpoint toEntity() {
    return Endpoint(
      id: id,
      pattern: pattern,
      matchType: MatchType.values.firstWhere(
            (e) => e.name == matchType,
        orElse: () => MatchType.exact,
      ),
      mode: EndpointMode.values.firstWhere(
            (e) => e.name == mode,
        orElse: () => EndpointMode.mock,
      ),
      mockResponse: mockResponse,
      delayMs: delayMs,
      targetUrl: targetUrl,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      isEnabled: isEnabled == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pattern': pattern,
      'matchType': matchType,
      'mode': mode,
      'mockResponse': mockResponse,
      'delayMs': delayMs,
      'targetUrl': targetUrl,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isEnabled': isEnabled,
    };
  }

  factory EndpointModel.fromMap(Map<String, dynamic> map) {
    return EndpointModel(
      id: map['id'],
      pattern: map['pattern'],
      matchType: map['matchType'],
      mode: map['mode'],
      mockResponse: map['mockResponse'],
      delayMs: map['delayMs'],
      targetUrl: map['targetUrl'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
      isEnabled: map['isEnabled'],
    );
  }
}
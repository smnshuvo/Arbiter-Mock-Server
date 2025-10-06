import 'package:equatable/equatable.dart';

enum EndpointMode { mock, passThrough }

enum MatchType { exact, wildcard, regex }

class Endpoint extends Equatable {
  final String id;
  final String pattern;
  final MatchType matchType;
  final EndpointMode mode;
  final String? mockResponse;
  final int delayMs;
  final String? targetUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isEnabled;

  const Endpoint({
    required this.id,
    required this.pattern,
    required this.matchType,
    required this.mode,
    this.mockResponse,
    this.delayMs = 0,
    this.targetUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isEnabled = true,
  });

  Endpoint copyWith({
    String? id,
    String? pattern,
    MatchType? matchType,
    EndpointMode? mode,
    String? mockResponse,
    int? delayMs,
    String? targetUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isEnabled,
  }) {
    return Endpoint(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      matchType: matchType ?? this.matchType,
      mode: mode ?? this.mode,
      mockResponse: mockResponse ?? this.mockResponse,
      delayMs: delayMs ?? this.delayMs,
      targetUrl: targetUrl ?? this.targetUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  @override
  List<Object?> get props => [
    id,
    pattern,
    matchType,
    mode,
    mockResponse,
    delayMs,
    targetUrl,
    createdAt,
    updatedAt,
    isEnabled,
  ];
}
import 'package:equatable/equatable.dart';

enum EndpointMode { mock, passThrough }

enum MatchType { exact, wildcard, regex }

enum ConditionalMatchType { queryParam, bodyField }

class ConditionalMock extends Equatable {
  final ConditionalMatchType type;
  final String fieldName;
  final String fieldValue;
  final String mockResponse;

  const ConditionalMock({
    required this.type,
    required this.fieldName,
    required this.fieldValue,
    required this.mockResponse,
  });

  @override
  List<Object?> get props => [type, fieldName, fieldValue, mockResponse];

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'fieldName': fieldName,
    'fieldValue': fieldValue,
    'mockResponse': mockResponse,
  };

  factory ConditionalMock.fromJson(Map<String, dynamic> json) {
    return ConditionalMock(
      type: ConditionalMatchType.values.firstWhere(
            (e) => e.name == json['type'],
        orElse: () => ConditionalMatchType.queryParam,
      ),
      fieldName: json['fieldName'],
      fieldValue: json['fieldValue'],
      mockResponse: json['mockResponse'],
    );
  }
}

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
  final List<ConditionalMock> conditionalMocks;
  final bool useConditionalMock;

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
    this.conditionalMocks = const [],
    this.useConditionalMock = false,
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
    List<ConditionalMock>? conditionalMocks,
    bool? useConditionalMock,
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
      conditionalMocks: conditionalMocks ?? this.conditionalMocks,
      useConditionalMock: useConditionalMock ?? this.useConditionalMock,
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
    conditionalMocks,
    useConditionalMock,
  ];
}
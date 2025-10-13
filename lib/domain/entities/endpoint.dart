import 'package:equatable/equatable.dart';

enum EndpointMode { mock, passThrough }

enum MatchType { exact, wildcard, regex }

enum ConditionalMatchType { queryParam, bodyField }

class ConditionalMock extends Equatable {
  final ConditionalMatchType type;
  final String fieldName;
  final String fieldValue;
  final String mockResponse;
  final int statusCode;

  const ConditionalMock({
    required this.type,
    required this.fieldName,
    required this.fieldValue,
    required this.mockResponse,
    this.statusCode = 200,
  });

  @override
  List<Object?> get props => [type, fieldName, fieldValue, mockResponse, statusCode];

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'fieldName': fieldName,
    'fieldValue': fieldValue,
    'mockResponse': mockResponse,
    'statusCode': statusCode,
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
      statusCode: json['statusCode'] ?? 200,
    );
  }
}

class Endpoint extends Equatable {
  final String id;
  final String pattern;
  final MatchType matchType;
  final EndpointMode mode;
  final String? mockResponse;
  final int statusCode;
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
    this.statusCode = 200,
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
    int? statusCode,
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
      statusCode: statusCode ?? this.statusCode,
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
    statusCode,
    delayMs,
    targetUrl,
    createdAt,
    updatedAt,
    isEnabled,
    conditionalMocks,
    useConditionalMock,
  ];
}

// Helper class for common HTTP status codes
class HttpStatusCode {
  static const int ok = 200;
  static const int created = 201;
  static const int noContent = 204;
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int conflict = 409;
  static const int internalServerError = 500;
  static const int badGateway = 502;
  static const int serviceUnavailable = 503;
  static const int gatewayTimeout = 504;

  static const List<int> commonCodes = [
    200, 201, 204, 400, 401, 403, 404, 409, 500, 502, 503, 504
  ];

  static String getStatusText(int code) {
    switch (code) {
      case 200: return '200 OK';
      case 201: return '201 Created';
      case 204: return '204 No Content';
      case 400: return '400 Bad Request';
      case 401: return '401 Unauthorized';
      case 403: return '403 Forbidden';
      case 404: return '404 Not Found';
      case 409: return '409 Conflict';
      case 500: return '500 Internal Server Error';
      case 502: return '502 Bad Gateway';
      case 503: return '503 Service Unavailable';
      case 504: return '504 Gateway Timeout';
      default: return '$code';
    }
  }
}
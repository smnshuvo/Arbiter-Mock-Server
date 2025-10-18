import 'interception_mode.dart';

class InterceptionRequest {
  final String id;
  final DateTime timestamp;
  final InterceptionType type; // request or response
  final InterceptionStatus status;

  // Request details
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;

  // Response details (only for response interception)
  final int? statusCode;
  final String? responseBody;
  final Map<String, String>? responseHeaders;

  InterceptionRequest({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.status,
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    this.statusCode,
    this.responseBody,
    this.responseHeaders,
  });

  InterceptionRequest copyWith({
    String? id,
    DateTime? timestamp,
    InterceptionType? type,
    InterceptionStatus? status,
    String? method,
    String? url,
    Map<String, String>? headers,
    String? body,
    int? statusCode,
    String? responseBody,
    Map<String, String>? responseHeaders,
  }) {
    return InterceptionRequest(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      status: status ?? this.status,
      method: method ?? this.method,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      statusCode: statusCode ?? this.statusCode,
      responseBody: responseBody ?? this.responseBody,
      responseHeaders: responseHeaders ?? this.responseHeaders,
    );
  }

  bool get isRequest => type == InterceptionType.request;
  bool get isResponse => type == InterceptionType.response;
  bool get isPending => status == InterceptionStatus.pending;
}

enum InterceptionType {
  request,
  response,
}

class InterceptionResponse {
  final bool cancelled;
  final String? modifiedMethod;
  final String? modifiedUrl;
  final Map<String, String>? modifiedHeaders;
  final String? modifiedBody;
  final int? modifiedStatusCode;

  InterceptionResponse({
    required this.cancelled,
    this.modifiedMethod,
    this.modifiedUrl,
    this.modifiedHeaders,
    this.modifiedBody,
    this.modifiedStatusCode,
  });

  factory InterceptionResponse.cancelled() {
    return InterceptionResponse(cancelled: true);
  }

  factory InterceptionResponse.passThrough() {
    return InterceptionResponse(cancelled: false);
  }

  factory InterceptionResponse.modified({
    String? method,
    String? url,
    Map<String, String>? headers,
    String? body,
    int? statusCode,
  }) {
    return InterceptionResponse(
      cancelled: false,
      modifiedMethod: method,
      modifiedUrl: url,
      modifiedHeaders: headers,
      modifiedBody: body,
      modifiedStatusCode: statusCode,
    );
  }
}
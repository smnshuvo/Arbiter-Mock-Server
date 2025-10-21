import 'package:equatable/equatable.dart';

enum RequestMethod {
  get,
  post,
  put,
  delete,
  patch,
  head,
  options,
}

extension RequestMethodExtension on RequestMethod {
  String get name {
    switch (this) {
      case RequestMethod.get:
        return 'GET';
      case RequestMethod.post:
        return 'POST';
      case RequestMethod.put:
        return 'PUT';
      case RequestMethod.delete:
        return 'DELETE';
      case RequestMethod.patch:
        return 'PATCH';
      case RequestMethod.head:
        return 'HEAD';
      case RequestMethod.options:
        return 'OPTIONS';
    }
  }

  static RequestMethod fromString(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return RequestMethod.get;
      case 'POST':
        return RequestMethod.post;
      case 'PUT':
        return RequestMethod.put;
      case 'DELETE':
        return RequestMethod.delete;
      case 'PATCH':
        return RequestMethod.patch;
      case 'HEAD':
        return RequestMethod.head;
      case 'OPTIONS':
        return RequestMethod.options;
      default:
        return RequestMethod.get;
    }
  }
}

enum LogType {
  mock,
  passThrough,
}

class RequestLog extends Equatable {
  final String id;
  final DateTime timestamp;
  final RequestMethod method;
  final String url;
  final Map<String, String> headers;
  final String? requestBody;
  final int statusCode;
  final String? responseBody;
  final int responseTimeMs;
  final LogType logType;
  final String? matchedEndpointId;
  final String? profileId; // NEW - track which profile handled the request

  const RequestLog({
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

  @override
  List<Object?> get props => [
    id,
    timestamp,
    method,
    url,
    headers,
    requestBody,
    statusCode,
    responseBody,
    responseTimeMs,
    logType,
    matchedEndpointId,
    profileId, // NEW
  ];
}
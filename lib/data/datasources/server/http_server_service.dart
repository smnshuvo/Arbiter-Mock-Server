import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:http/http.dart' as http;
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/request_log.dart';
import '../../models/request_log_model.dart';
import '../local/log_local_datasource.dart';

class HttpServerService {
  HttpServer? _server;
  int _port = 8080;
  String? _globalPassThroughUrl;
  bool _autoPassThrough = false;
  final LogLocalDataSource logDataSource;
  final Function() onEndpointsNeeded;

  HttpServerService({
    required this.logDataSource,
    required this.onEndpointsNeeded,
  });

  bool get isRunning => _server != null;

  String get serverUrl => 'http://localhost:$_port';

  int get port => _port;

  set port(int value) => _port = value;

  String? get globalPassThroughUrl => _globalPassThroughUrl;

  set globalPassThroughUrl(String? value) => _globalPassThroughUrl = value;

  bool get autoPassThrough => _autoPassThrough;

  set autoPassThrough(bool value) => _autoPassThrough = value;

  Future<void> start(int port) async {
    if (_server != null) {
      throw Exception('Server is already running');
    }

    _port = port;

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
    print('Server started on $serverUrl');
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      print('Server stopped');
    }
  }

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders());
        }

        final response = await handler(request);
        return response.change(headers: _corsHeaders());
      };
    };
  }

  Map<String, String> _corsHeaders() {
    return {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
    };
  }

  Future<Response> _handleRequest(Request request) async {
    final startTime = DateTime.now();
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      // Get current endpoints
      onEndpointsNeeded();
      final endpoints = await _getCurrentEndpoints();

      // Read request body
      final requestBody = await request.readAsString();

      // Find matching endpoint
      final matchedEndpoint = _findMatchingEndpoint(request.url.toString(), endpoints);

      Response response;
      LogType logType;
      String? matchedEndpointId;

      if (matchedEndpoint != null && matchedEndpoint.isEnabled) {
        matchedEndpointId = matchedEndpoint.id;

        if (matchedEndpoint.mode == EndpointMode.mock) {
          // Check for conditional mocks
          String? mockResponseToUse;

          if (matchedEndpoint.useConditionalMock && matchedEndpoint.conditionalMocks.isNotEmpty) {
            mockResponseToUse = _findConditionalMock(
              request,
              requestBody,
              matchedEndpoint.conditionalMocks,
            );
          }

          // Use conditional mock or default mock response
          mockResponseToUse ??= matchedEndpoint.mockResponse;

          // Return mock response
          if (matchedEndpoint.delayMs > 0) {
            await Future.delayed(Duration(milliseconds: matchedEndpoint.delayMs));
          }

          response = Response.ok(
            mockResponseToUse ?? '{}',
            headers: {'Content-Type': 'application/json'},
          );
          logType = LogType.mock;
        } else {
          // Pass through to actual server
          response = await _passThrough(request, matchedEndpoint, requestBody);
          logType = LogType.passThrough;
        }
      } else if (_autoPassThrough && _globalPassThroughUrl != null) {
        // Auto pass-through for unmatched endpoints
        response = await _autoPassThroughRequest(request, requestBody);
        logType = LogType.passThrough;
      } else {
        // No matching endpoint, return 404
        response = Response.notFound(
          jsonEncode({'error': 'No matching endpoint configured'}),
          headers: {'Content-Type': 'application/json'},
        );
        logType = LogType.mock;
      }

      // Log the request
      final endTime = DateTime.now();
      final responseTimeMs = endTime.difference(startTime).inMilliseconds;

      await _logRequest(
        requestId,
        request,
        requestBody,
        response,
        responseTimeMs,
        logType,
        matchedEndpointId,
      );

      return response;
    } catch (e) {
      print('Error handling request: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  String? _findConditionalMock(
      Request request,
      String requestBody,
      List<ConditionalMock> conditionalMocks,
      ) {
    for (final conditionalMock in conditionalMocks) {
      if (conditionalMock.type == ConditionalMatchType.queryParam) {
        // Check query parameters
        final queryValue = request.url.queryParameters[conditionalMock.fieldName];
        if (queryValue == conditionalMock.fieldValue) {
          return conditionalMock.mockResponse;
        }
      } else if (conditionalMock.type == ConditionalMatchType.bodyField) {
        // Check request body field
        if (requestBody.isNotEmpty) {
          try {
            final Map<String, dynamic> body = jsonDecode(requestBody);
            final fieldValue = body[conditionalMock.fieldName]?.toString();
            if (fieldValue == conditionalMock.fieldValue) {
              return conditionalMock.mockResponse;
            }
          } catch (e) {
            print('Error parsing request body for conditional mock: $e');
          }
        }
      }
    }
    return null; // No condition matched, use default
  }

  Future<Response> _autoPassThroughRequest(
      Request request,
      String requestBody,
      ) async {
    try {
      if (_globalPassThroughUrl == null || _globalPassThroughUrl!.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'No global pass-through URL configured'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Build the full URL by appending the request path to the base URL
      String baseUrl = _globalPassThroughUrl!;
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      final path = request.url.path;
      final query = request.url.query;
      String fullUrl = '$baseUrl/$path';
      if (query.isNotEmpty) {
        fullUrl += '?$query';
      }

      final uri = Uri.parse(fullUrl);
      final method = request.method.toUpperCase();

      // Prepare headers
      final headers = Map<String, String>.from(request.headers);
      headers.remove('host');

      http.Response response;

      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: requestBody);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: requestBody);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers, body: requestBody);
          break;
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: requestBody);
          break;
        case 'HEAD':
          response = await http.head(uri, headers: headers);
          break;
        default:
          return Response.badRequest(
            body: jsonEncode({'error': 'Unsupported HTTP method'}),
            headers: {'Content-Type': 'application/json'},
          );
      }

      return Response(
        response.statusCode,
        body: response.body,
        headers: Map<String, String>.from(response.headers),
      );
    } catch (e) {
      print('Error in auto pass-through: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Auto pass-through failed: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Endpoint? _findMatchingEndpoint(String url, List<Endpoint> endpoints) {
    for (final endpoint in endpoints) {
      if (!endpoint.isEnabled) continue;

      switch (endpoint.matchType) {
        case MatchType.exact:
          if (url == endpoint.pattern || url.endsWith(endpoint.pattern)) {
            return endpoint;
          }
          break;
        case MatchType.wildcard:
          final pattern = endpoint.pattern.replaceAll('*', '.*');
          if (RegExp(pattern).hasMatch(url)) {
            return endpoint;
          }
          break;
        case MatchType.regex:
          if (RegExp(endpoint.pattern).hasMatch(url)) {
            return endpoint;
          }
          break;
      }
    }
    return null;
  }

  Future<Response> _passThrough(
      Request request,
      Endpoint endpoint,
      String requestBody,
      ) async {
    try {
      final targetUrl = endpoint.targetUrl;
      if (targetUrl == null || targetUrl.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'No target URL configured'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final uri = Uri.parse(targetUrl);
      final method = request.method.toUpperCase();

      // Prepare headers
      final headers = Map<String, String>.from(request.headers);
      headers.remove('host');

      http.Response response;

      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: requestBody);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: requestBody);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers, body: requestBody);
          break;
        case 'PATCH':
          response = await http.patch(uri, headers: headers, body: requestBody);
          break;
        case 'HEAD':
          response = await http.head(uri, headers: headers);
          break;
        default:
          return Response.badRequest(
            body: jsonEncode({'error': 'Unsupported HTTP method'}),
            headers: {'Content-Type': 'application/json'},
          );
      }

      return Response(
        response.statusCode,
        body: response.body,
        headers: Map<String, String>.from(response.headers),
      );
    } catch (e) {
      print('Error in pass-through: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Pass-through failed: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<void> _logRequest(
      String id,
      Request request,
      String requestBody,
      Response response,
      int responseTimeMs,
      LogType logType,
      String? matchedEndpointId,
      ) async {
    try {
      final responseBody = await response.readAsString();

      final log = RequestLog(
        id: id,
        timestamp: DateTime.now(),
        method: RequestMethodExtension.fromString(request.method),
        url: request.url.toString(),
        headers: Map<String, String>.from(request.headers),
        requestBody: requestBody.isNotEmpty ? requestBody : null,
        statusCode: response.statusCode,
        responseBody: responseBody.isNotEmpty ? responseBody : null,
        responseTimeMs: responseTimeMs,
        logType: logType,
        matchedEndpointId: matchedEndpointId,
      );

      final logModel = RequestLogModel.fromEntity(log);
      await logDataSource.insertLog(logModel);
    } catch (e) {
      print('Error logging request: $e');
    }
  }

  // This will be called from the repository to get current endpoints
  List<Endpoint> _cachedEndpoints = [];

  void updateEndpoints(List<Endpoint> endpoints) {
    _cachedEndpoints = endpoints;
  }

  Future<List<Endpoint>> _getCurrentEndpoints() async {
    return _cachedEndpoints;
  }
}
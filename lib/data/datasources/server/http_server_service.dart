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
import '../../../core/utils/network_utils.dart';
import 'interception_manager.dart';

class HttpServerService {
  HttpServer? _server;
  int _port = 8080;
  bool _useDeviceIp = false;
  String? _currentIpAddress;
  String? _globalPassThroughUrl;
  bool _autoPassThrough = false;
  final LogLocalDataSource logDataSource;
  final Function() onEndpointsNeeded;
  final InterceptionManager interceptionManager;

  HttpServerService({
    required this.logDataSource,
    required this.onEndpointsNeeded,
    required this.interceptionManager,
  });

  bool get isRunning => _server != null;

  String get serverUrl {
    final host = _useDeviceIp && _currentIpAddress != null
        ? _currentIpAddress!
        : 'localhost';
    return 'http://$host:$_port';
  }

  int get port => _port;

  set port(int value) => _port = value;

  bool get useDeviceIp => _useDeviceIp;

  set useDeviceIp(bool value) => _useDeviceIp = value;

  String? get currentIpAddress => _currentIpAddress;

  String? get globalPassThroughUrl => _globalPassThroughUrl;

  set globalPassThroughUrl(String? value) => _globalPassThroughUrl = value;

  bool get autoPassThrough => _autoPassThrough;

  set autoPassThrough(bool value) => _autoPassThrough = value;

  Future<void> start(int port, {bool useDeviceIp = false}) async {
    if (_server != null) {
      throw Exception('Server is already running');
    }

    _port = port;
    _useDeviceIp = useDeviceIp;

    // Get device IP if needed
    if (_useDeviceIp) {
      _currentIpAddress = await NetworkUtils.getDeviceIpAddress();
      if (_currentIpAddress == null) {
        throw Exception('Could not determine device IP address');
      }
    }

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(_handleRequest);

    // Bind to appropriate address
    final address = _useDeviceIp
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;

    _server = await shelf_io.serve(handler, address, port);
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
        // Merge CORS headers with existing headers instead of replacing
        final mergedHeaders = Map<String, String>.from(response.headers);
        mergedHeaders.addAll(_corsHeaders());
        return response.change(headers: mergedHeaders);
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
      // Read request body
      String requestBody = await request.readAsString();
      String method = request.method;
      String url = request.url.toString();
      Map<String, String> headers = Map<String, String>.from(request.headers);

      // 1. Check if request interception is enabled
      if (interceptionManager.shouldInterceptRequests) {
        final interceptionResult = await interceptionManager.interceptRequest(
          id: '$requestId-request',
          method: method,
          url: url,
          headers: headers,
          body: requestBody.isNotEmpty ? requestBody : null,
        );

        if (interceptionResult.cancelled) {
          return Response(499,
              body: jsonEncode({'error': 'Request cancelled by user'}),
              headers: {'Content-Type': 'application/json'});
        }

        // Apply modifications if any
        method = interceptionResult.modifiedMethod ?? method;
        url = interceptionResult.modifiedUrl ?? url;
        headers = interceptionResult.modifiedHeaders ?? headers;
        requestBody = interceptionResult.modifiedBody ?? requestBody;
      }

      // Get current endpoints
      onEndpointsNeeded();
      final endpoints = await _getCurrentEndpoints();

      // Find matching endpoint
      final matchedEndpoint = _findMatchingEndpoint(url, endpoints);

      String responseBody;
      int statusCode;
      Map<String, String> responseHeaders;
      LogType logType;
      String? matchedEndpointId;

      if (matchedEndpoint != null && matchedEndpoint.isEnabled) {
        matchedEndpointId = matchedEndpoint.id;

        if (matchedEndpoint.mode == EndpointMode.mock) {
          // Check for conditional mocks
          String? mockResponseToUse;
          int statusCodeToUse = matchedEndpoint.statusCode;

          if (matchedEndpoint.useConditionalMock &&
              matchedEndpoint.conditionalMocks.isNotEmpty) {
            final conditionalResult = _findConditionalMock(
              request,
              requestBody,
              matchedEndpoint.conditionalMocks,
            );

            if (conditionalResult != null) {
              mockResponseToUse = conditionalResult['mockResponse'];
              statusCodeToUse = conditionalResult['statusCode'];
            }
          }

          // Use conditional mock or default mock response
          mockResponseToUse ??= matchedEndpoint.mockResponse;

          // Return mock response
          if (matchedEndpoint.delayMs > 0) {
            await Future.delayed(
                Duration(milliseconds: matchedEndpoint.delayMs));
          }

          responseBody = mockResponseToUse ?? '{}';
          statusCode = statusCodeToUse;
          responseHeaders = {'Content-Type': 'application/json'};
          logType = LogType.mock;
        } else {
          // Pass through to actual server
          final passThroughResult =
          await _passThrough(request, matchedEndpoint, requestBody);
          responseBody = passThroughResult['body'] as String;
          statusCode = passThroughResult['statusCode'] as int;
          responseHeaders =
          Map<String, String>.from(passThroughResult['headers'] as Map);
          logType = LogType.passThrough;
        }
      } else if (_autoPassThrough && _globalPassThroughUrl != null) {
        // Auto pass-through for unmatched endpoints
        final passThroughResult =
        await _autoPassThroughRequest(request, requestBody);
        responseBody = passThroughResult['body'] as String;
        statusCode = passThroughResult['statusCode'] as int;
        responseHeaders =
        Map<String, String>.from(passThroughResult['headers'] as Map);
        logType = LogType.passThrough;
      } else {
        // No matching endpoint, return 404
        responseBody = jsonEncode({'error': 'No matching endpoint configured'});
        statusCode = 404;
        responseHeaders = {'Content-Type': 'application/json'};
        logType = LogType.mock;
      }

      // 2. Check if response interception is enabled
      if (interceptionManager.shouldInterceptResponses) {
        final interceptionResult = await interceptionManager.interceptResponse(
          id: '$requestId-response',
          method: method,
          url: url,
          headers: headers,
          body: requestBody.isNotEmpty ? requestBody : null,
          statusCode: statusCode,
          responseBody: responseBody,
          responseHeaders: responseHeaders,
        );

        if (interceptionResult.cancelled) {
          return Response(499,
              body: jsonEncode({'error': 'Response cancelled by user'}),
              headers: {'Content-Type': 'application/json'});
        }

        // Apply modifications if any
        statusCode = interceptionResult.modifiedStatusCode ?? statusCode;
        responseBody = interceptionResult.modifiedBody ?? responseBody;
        responseHeaders =
            interceptionResult.modifiedHeaders ?? responseHeaders;
      }

      // Clean up headers that can cause conflicts with Shelf
      responseHeaders.remove('transfer-encoding');
      responseHeaders.remove('Transfer-Encoding');
      responseHeaders.remove('content-encoding');
      responseHeaders.remove('Content-Encoding');

      // Ensure Content-Type is set
      if (!responseHeaders.containsKey('content-type') &&
          !responseHeaders.containsKey('Content-Type')) {
        responseHeaders['Content-Type'] = 'application/json';
      }

      // Set proper Content-Length
      final bodyBytes = utf8.encode(responseBody);
      responseHeaders['Content-Length'] = bodyBytes.length.toString();

      // Log the request
      final endTime = DateTime.now();
      final responseTimeMs = endTime.difference(startTime).inMilliseconds;

      await _logRequest(
        requestId,
        request,
        requestBody,
        responseBody,
        statusCode,
        responseTimeMs,
        logType,
        matchedEndpointId,
      );

      // Return the response with proper headers and custom status code
      return Response(statusCode, body: responseBody, headers: responseHeaders);
    } catch (e) {
      print('Error handling request: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Map<String, dynamic>? _findConditionalMock(
      Request request,
      String requestBody,
      List<ConditionalMock> conditionalMocks,
      ) {
    for (final conditionalMock in conditionalMocks) {
      if (conditionalMock.type == ConditionalMatchType.queryParam) {
        // Check query parameters
        final queryValue = request.url.queryParameters[conditionalMock.fieldName];
        if (queryValue == conditionalMock.fieldValue) {
          return {
            'mockResponse': conditionalMock.mockResponse,
            'statusCode': conditionalMock.statusCode,
          };
        }
      } else if (conditionalMock.type == ConditionalMatchType.bodyField) {
        // Check request body field
        if (requestBody.isNotEmpty) {
          try {
            final Map<String, dynamic> body = jsonDecode(requestBody);
            final fieldValue = body[conditionalMock.fieldName]?.toString();
            if (fieldValue == conditionalMock.fieldValue) {
              return {
                'mockResponse': conditionalMock.mockResponse,
                'statusCode': conditionalMock.statusCode,
              };
            }
          } catch (e) {
            print('Error parsing request body for conditional mock: $e');
          }
        }
      }
    }
    return null; // No condition matched, use default
  }

  Future<Map<String, dynamic>> _autoPassThroughRequest(
      Request request,
      String requestBody,
      ) async {
    try {
      if (_globalPassThroughUrl == null || _globalPassThroughUrl!.isEmpty) {
        return {
          'body': jsonEncode({'error': 'No global pass-through URL configured'}),
          'statusCode': 400,
          'headers': {'Content-Type': 'application/json'},
        };
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
          return {
            'body': jsonEncode({'error': 'Unsupported HTTP method'}),
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
          };
      }

      // Ensure we have a proper response body (empty string for HEAD requests)
      final body = method == 'HEAD' ? '' : response.body;

      return {
        'body': body,
        'statusCode': response.statusCode,
        'headers': Map<String, String>.from(response.headers),
      };
    } catch (e) {
      print('Error in auto pass-through: $e');
      return {
        'body': jsonEncode({'error': 'Auto pass-through failed: $e'}),
        'statusCode': 500,
        'headers': {'Content-Type': 'application/json'},
      };
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

  Future<Map<String, dynamic>> _passThrough(
      Request request,
      Endpoint endpoint,
      String requestBody,
      ) async {
    try {
      final targetUrl = endpoint.targetUrl;
      if (targetUrl == null || targetUrl.isEmpty) {
        return {
          'body': jsonEncode({'error': 'No target URL configured'}),
          'statusCode': 400,
          'headers': {'Content-Type': 'application/json'},
        };
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
          return {
            'body': jsonEncode({'error': 'Unsupported HTTP method'}),
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
          };
      }

      // Ensure we have a proper response body (empty string for HEAD requests)
      final body = method == 'HEAD' ? '' : response.body;

      return {
        'body': body,
        'statusCode': response.statusCode,
        'headers': Map<String, String>.from(response.headers),
      };
    } catch (e) {
      print('Error in pass-through: $e');
      return {
        'body': jsonEncode({'error': 'Pass-through failed: $e'}),
        'statusCode': 500,
        'headers': {'Content-Type': 'application/json'},
      };
    }
  }

  Future<void> _logRequest(
      String id,
      Request request,
      String requestBody,
      String responseBody,
      int statusCode,
      int responseTimeMs,
      LogType logType,
      String? matchedEndpointId,
      ) async {
    try {
      final log = RequestLog(
        id: id,
        timestamp: DateTime.now(),
        method: RequestMethodExtension.fromString(request.method),
        url: request.url.toString(),
        headers: Map<String, String>.from(request.headers),
        requestBody: requestBody.isNotEmpty ? requestBody : null,
        statusCode: statusCode,
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
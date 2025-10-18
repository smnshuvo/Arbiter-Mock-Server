import 'dart:async';
import '../../../domain/entities/interception_request.dart';
import '../../../domain/entities/interception_mode.dart';

class InterceptionManager {
  final StreamController<InterceptionRequest> _controller =
  StreamController<InterceptionRequest>.broadcast();
  final Map<String, Completer<InterceptionResponse>> _pendingRequests = {};
  InterceptionMode _mode = InterceptionMode.none;
  int _autoTimeoutSeconds = 30;

  Stream<InterceptionRequest> get interceptionStream => _controller.stream;

  InterceptionMode get mode => _mode;

  void setMode(InterceptionMode mode) {
    _mode = mode;
  }

  int get autoTimeout => _autoTimeoutSeconds;

  void setAutoTimeout(int seconds) {
    _autoTimeoutSeconds = seconds;
  }

  bool get isEnabled => _mode != InterceptionMode.none;

  bool get shouldInterceptRequests => _mode.interceptsRequests;

  bool get shouldInterceptResponses => _mode.interceptsResponses;

  /// Intercept a request before it's processed
  Future<InterceptionResponse> interceptRequest({
    required String id,
    required String method,
    required String url,
    required Map<String, String> headers,
    String? body,
  }) async {
    if (!shouldInterceptRequests) {
      return InterceptionResponse.passThrough();
    }

    final interception = InterceptionRequest(
      id: id,
      timestamp: DateTime.now(),
      type: InterceptionType.request,
      status: InterceptionStatus.pending,
      method: method,
      url: url,
      headers: headers,
      body: body,
    );

    return _waitForUserAction(interception);
  }

  /// Intercept a response before it's returned
  Future<InterceptionResponse> interceptResponse({
    required String id,
    required String method,
    required String url,
    required Map<String, String> headers,
    String? body,
    required int statusCode,
    required String responseBody,
    required Map<String, String> responseHeaders,
  }) async {
    if (!shouldInterceptResponses) {
      return InterceptionResponse.passThrough();
    }

    final interception = InterceptionRequest(
      id: id,
      timestamp: DateTime.now(),
      type: InterceptionType.response,
      status: InterceptionStatus.pending,
      method: method,
      url: url,
      headers: headers,
      body: body,
      statusCode: statusCode,
      responseBody: responseBody,
      responseHeaders: responseHeaders,
    );

    return _waitForUserAction(interception);
  }

  Future<InterceptionResponse> _waitForUserAction(
      InterceptionRequest interception) async {
    final completer = Completer<InterceptionResponse>();
    _pendingRequests[interception.id] = completer;

    // Emit to stream for UI
    _controller.add(interception);

    // Set up timeout
    final timeout = Future.delayed(
      Duration(seconds: _autoTimeoutSeconds),
          () {
        if (!completer.isCompleted) {
          completer.complete(InterceptionResponse.passThrough());
          _pendingRequests.remove(interception.id);
        }
      },
    );

    try {
      return await completer.future;
    } finally {
      timeout.ignore();
    }
  }

  /// User modifies and continues
  void modifyAndContinue(
      String id, {
        String? method,
        String? url,
        Map<String, String>? headers,
        String? body,
        int? statusCode,
      }) {
    final completer = _pendingRequests.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(InterceptionResponse.modified(
        method: method,
        url: url,
        headers: headers,
        body: body,
        statusCode: statusCode,
      ));
    }
  }

  /// User continues without modification
  void continueWithoutModification(String id) {
    final completer = _pendingRequests.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(InterceptionResponse.passThrough());
    }
  }

  /// User cancels the request
  void cancelRequest(String id) {
    final completer = _pendingRequests.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(InterceptionResponse.cancelled());
    }
  }

  void dispose() {
    _controller.close();
    // Complete all pending requests
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(InterceptionResponse.passThrough());
      }
    }
    _pendingRequests.clear();
  }
}
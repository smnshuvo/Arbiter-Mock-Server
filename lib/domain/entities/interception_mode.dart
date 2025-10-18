enum InterceptionMode {
  none,           // No interception
  requestOnly,    // Intercept and modify requests only
  responseOnly,   // Intercept and modify responses only
  both,           // Intercept both request and response
}

enum InterceptionStatus {
  pending,        // Waiting for user action
  modified,       // User modified it
  passed,         // User passed it through unchanged
  cancelled,      // User cancelled the request
}

extension InterceptionModeExtension on InterceptionMode {
  String get displayName {
    switch (this) {
      case InterceptionMode.none:
        return 'None';
      case InterceptionMode.requestOnly:
        return 'Request Only';
      case InterceptionMode.responseOnly:
        return 'Response Only';
      case InterceptionMode.both:
        return 'Both';
    }
  }

  bool get interceptsRequests =>
      this == InterceptionMode.requestOnly || this == InterceptionMode.both;

  bool get interceptsResponses =>
      this == InterceptionMode.responseOnly || this == InterceptionMode.both;
}
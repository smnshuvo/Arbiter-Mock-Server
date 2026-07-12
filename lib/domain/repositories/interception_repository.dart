import '../entities/interception_request.dart';
import '../entities/interception_mode.dart';

abstract class InterceptionRepository {
  /// Stream of pending interceptions that need user action
  Stream<InterceptionRequest> watchPendingInterceptions();

  /// Modify and continue with the request/response
  Future<void> modifyAndContinue(
      String id, {
        String? method,
        String? url,
        Map<String, String>? headers,
        String? body,
        int? statusCode,
      });

  /// Continue without any modifications
  Future<void> continueWithoutModification(String id);

  /// Cancel the request
  Future<void> cancelRequest(String id);

  /// Set interception mode
  Future<void> setInterceptionMode(InterceptionMode mode);

  /// Get current interception mode
  InterceptionMode getInterceptionMode();

  /// Set auto-continue timeout in seconds
  Future<void> setAutoTimeout(int seconds);

  /// Get current auto-timeout
  int getAutoTimeout();

  /// Restrict interception to URLs matching one of these patterns
  /// (`*` wildcards supported). An empty list intercepts every URL.
  Future<void> setWhitelist(List<String> patterns);

  /// Get the current whitelist patterns
  List<String> getWhitelist();

  /// Whether the patterns are an allow-list or a deny-list
  Future<void> setUrlListMode(UrlListMode mode);

  /// Get the current allow-list/deny-list mode
  UrlListMode getUrlListMode();
}
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
}
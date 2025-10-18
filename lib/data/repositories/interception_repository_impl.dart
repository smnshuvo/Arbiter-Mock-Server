import '../../domain/entities/interception_request.dart';
import '../../domain/entities/interception_mode.dart';
import '../../domain/repositories/interception_repository.dart';
import '../datasources/server/interception_manager.dart';

class InterceptionRepositoryImpl implements InterceptionRepository {
  final InterceptionManager manager;

  InterceptionRepositoryImpl(this.manager);

  @override
  Stream<InterceptionRequest> watchPendingInterceptions() {
    return manager.interceptionStream;
  }

  @override
  Future<void> modifyAndContinue(
      String id, {
        String? method,
        String? url,
        Map<String, String>? headers,
        String? body,
        int? statusCode,
      }) async {
    manager.modifyAndContinue(
      id,
      method: method,
      url: url,
      headers: headers,
      body: body,
      statusCode: statusCode,
    );
  }

  @override
  Future<void> continueWithoutModification(String id) async {
    manager.continueWithoutModification(id);
  }

  @override
  Future<void> cancelRequest(String id) async {
    manager.cancelRequest(id);
  }

  @override
  Future<void> setInterceptionMode(InterceptionMode mode) async {
    manager.setMode(mode);
  }

  @override
  InterceptionMode getInterceptionMode() {
    return manager.mode;
  }

  @override
  Future<void> setAutoTimeout(int seconds) async {
    manager.setAutoTimeout(seconds);
  }

  @override
  int getAutoTimeout() {
    return manager.autoTimeout;
  }
}
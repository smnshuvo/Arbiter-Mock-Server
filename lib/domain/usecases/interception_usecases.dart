import '../entities/interception_request.dart';
import '../entities/interception_mode.dart';
import '../repositories/interception_repository.dart';

class WatchPendingInterceptions {
  final InterceptionRepository repository;

  WatchPendingInterceptions(this.repository);

  Stream<InterceptionRequest> call() {
    return repository.watchPendingInterceptions();
  }
}

class ModifyAndContinue {
  final InterceptionRepository repository;

  ModifyAndContinue(this.repository);

  Future<void> call(
      String id, {
        String? method,
        String? url,
        Map<String, String>? headers,
        String? body,
        int? statusCode,
      }) async {
    await repository.modifyAndContinue(
      id,
      method: method,
      url: url,
      headers: headers,
      body: body,
      statusCode: statusCode,
    );
  }
}

class ContinueWithoutModification {
  final InterceptionRepository repository;

  ContinueWithoutModification(this.repository);

  Future<void> call(String id) async {
    await repository.continueWithoutModification(id);
  }
}

class CancelInterception {
  final InterceptionRepository repository;

  CancelInterception(this.repository);

  Future<void> call(String id) async {
    await repository.cancelRequest(id);
  }
}

class SetInterceptionMode {
  final InterceptionRepository repository;

  SetInterceptionMode(this.repository);

  Future<void> call(InterceptionMode mode) async {
    await repository.setInterceptionMode(mode);
  }
}

class GetInterceptionMode {
  final InterceptionRepository repository;

  GetInterceptionMode(this.repository);

  InterceptionMode call() {
    return repository.getInterceptionMode();
  }
}

class SetInterceptionTimeout {
  final InterceptionRepository repository;

  SetInterceptionTimeout(this.repository);

  Future<void> call(int seconds) async {
    await repository.setAutoTimeout(seconds);
  }
}

class GetInterceptionTimeout {
  final InterceptionRepository repository;

  GetInterceptionTimeout(this.repository);

  int call() {
    return repository.getAutoTimeout();
  }
}
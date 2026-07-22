import '../entities/endpoint.dart';
import '../entities/prompt.dart';
import '../repositories/prompt_repository.dart';

class WatchActivePrompt {
  final PromptRepository repository;

  WatchActivePrompt(this.repository);

  Stream<PendingPrompt?> call() => repository.watchActivePrompt();
}

class ResolvePrompt {
  final PromptRepository repository;

  ResolvePrompt(this.repository);

  void call(String id, PromptCandidateResponse candidate) {
    repository.resolve(id, candidate);
  }
}

class ResolvePromptEdited {
  final PromptRepository repository;

  ResolvePromptEdited(this.repository);

  void call(String id, {required int statusCode, required String body}) {
    repository.resolveEdited(id, statusCode: statusCode, body: body);
  }
}

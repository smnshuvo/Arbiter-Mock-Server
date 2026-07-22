import '../../domain/entities/endpoint.dart';
import '../../domain/entities/prompt.dart';
import '../../domain/repositories/prompt_repository.dart';
import '../datasources/server/prompt_interception_manager.dart';

class PromptRepositoryImpl implements PromptRepository {
  final PromptInterceptionManager manager;

  PromptRepositoryImpl(this.manager);

  @override
  Stream<PendingPrompt?> watchActivePrompt() => manager.promptStream;

  @override
  void resolve(String id, PromptCandidateResponse candidate) {
    manager.resolve(id, candidate);
  }

  @override
  void resolveEdited(String id, {required int statusCode, required String body}) {
    manager.resolveEdited(id, statusCode: statusCode, body: body);
  }
}

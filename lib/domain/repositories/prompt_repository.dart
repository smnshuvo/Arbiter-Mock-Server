import '../entities/endpoint.dart';
import '../entities/prompt.dart';

abstract class PromptRepository {
  /// Emits the prompt currently shown to the developer, or `null` once the
  /// queue drains.
  Stream<PendingPrompt?> watchActivePrompt();

  /// Developer picked [candidate] as-is for prompt [id].
  void resolve(String id, PromptCandidateResponse candidate);

  /// Developer edited a candidate's body/status before serving it.
  void resolveEdited(String id, {required int statusCode, required String body});
}

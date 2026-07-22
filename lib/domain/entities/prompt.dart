import 'endpoint.dart';

/// A live request waiting on the developer to pick (or edit) one of an
/// endpoint's [PromptCandidateResponse]s. Distinct from [InterceptionRequest]
/// — that's a single-value request/response editor wired to the global
/// [InterceptionMode] toggle; this fires from inside per-endpoint
/// conditional-mock resolution and always offers a set of named candidates
/// rather than one editable payload.
class PendingPrompt {
  final String id;
  final String endpointId;
  final String method;
  final String path;
  final List<PromptCandidateResponse> candidates;
  final DateTime timestamp;
  final int timeoutSeconds;

  const PendingPrompt({
    required this.id,
    required this.endpointId,
    required this.method,
    required this.path,
    required this.candidates,
    required this.timestamp,
    this.timeoutSeconds = 29,
  });
}

/// The resolved response to serve for a [PendingPrompt] — either a candidate
/// as-is, or one the developer edited before serving.
class PromptChoice {
  final int statusCode;
  final String body;

  const PromptChoice({required this.statusCode, required this.body});
}

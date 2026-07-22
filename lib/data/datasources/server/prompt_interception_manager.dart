import 'dart:async';
import 'dart:collection';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/prompt.dart';

/// Server-side counterpart of the "Prompt" conditional mode: holds the
/// matching request open until the developer resolves it, showing prompts
/// one at a time (queued) with an independent timeout per prompt.
class PromptInterceptionManager {
  final StreamController<PendingPrompt?> _controller =
      StreamController<PendingPrompt?>.broadcast();
  final Map<String, Completer<PromptChoice>> _pendingCompleters = {};
  final Queue<PendingPrompt> _queue = Queue<PendingPrompt>();
  PendingPrompt? _active;
  int _timeoutSeconds = 29;

  /// Emits the prompt currently shown to the developer, or `null` when the
  /// queue drains. Requests behind it are queued, not dropped.
  Stream<PendingPrompt?> get promptStream => _controller.stream;

  PendingPrompt? get active => _active;

  int get autoTimeout => _timeoutSeconds;

  void setAutoTimeout(int seconds) => _timeoutSeconds = seconds;

  /// Blocks until the developer resolves [id] (or its timeout elapses).
  Future<PromptChoice> requestChoice({
    required String id,
    required String endpointId,
    required String method,
    required String path,
    required List<PromptCandidateResponse> candidates,
  }) async {
    if (candidates.isEmpty) {
      // Misconfigured endpoint (prompt mode on, no candidates saved yet) —
      // fall back rather than hang the request forever.
      return const PromptChoice(statusCode: 200, body: '{}');
    }

    final completer = Completer<PromptChoice>();
    _pendingCompleters[id] = completer;

    final prompt = PendingPrompt(
      id: id,
      endpointId: endpointId,
      method: method,
      path: path,
      candidates: candidates,
      timestamp: DateTime.now(),
      timeoutSeconds: _timeoutSeconds,
    );

    _enqueue(prompt);

    // Each prompt's timeout clock runs from creation, not from when it
    // becomes the visible/active one in the queue.
    final timeout = Future.delayed(Duration(seconds: _timeoutSeconds), () {
      if (!completer.isCompleted) {
        resolve(id, candidates.first);
      }
    });

    try {
      return await completer.future;
    } finally {
      timeout.ignore();
    }
  }

  void _enqueue(PendingPrompt prompt) {
    if (_active == null) {
      _active = prompt;
      _controller.add(_active);
    } else {
      _queue.add(prompt);
    }
  }

  void _advance() {
    if (_queue.isNotEmpty) {
      _active = _queue.removeFirst();
    } else {
      _active = null;
    }
    _controller.add(_active);
  }

  /// Developer picked [candidate] as-is for prompt [id].
  void resolve(String id, PromptCandidateResponse candidate) {
    _resolveWith(
      id,
      PromptChoice(statusCode: candidate.statusCode, body: candidate.body),
    );
  }

  /// Developer edited a candidate's body/status before serving it.
  void resolveEdited(String id, {required int statusCode, required String body}) {
    _resolveWith(id, PromptChoice(statusCode: statusCode, body: body));
  }

  void _resolveWith(String id, PromptChoice choice) {
    final completer = _pendingCompleters.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(choice);
    }
    if (_active?.id == id) {
      _advance();
    } else {
      _queue.removeWhere((p) => p.id == id);
    }
  }

  void dispose() {
    _controller.close();
    for (final completer in _pendingCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(const PromptChoice(statusCode: 200, body: '{}'));
      }
    }
    _pendingCompleters.clear();
    _queue.clear();
    _active = null;
  }
}

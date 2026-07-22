import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/prompt_usecases.dart';
import 'prompt_event.dart';
import 'prompt_state.dart';

class PromptBloc extends Bloc<PromptEvent, PromptState> {
  final WatchActivePrompt watchActivePrompt;
  final ResolvePrompt resolvePrompt;
  final ResolvePromptEdited resolvePromptEdited;

  StreamSubscription? _subscription;

  PromptBloc({
    required this.watchActivePrompt,
    required this.resolvePrompt,
    required this.resolvePromptEdited,
  }) : super(PromptInitial()) {
    on<StartWatchingPrompts>(_onStartWatching);
    on<StopWatchingPrompts>(_onStopWatching);
    on<ActivePromptChanged>(_onActivePromptChanged);
    on<UsePromptCandidateEvent>(_onUseCandidate);
    on<ServeEditedPromptEvent>(_onServeEdited);
  }

  Future<void> _onStartWatching(
      StartWatchingPrompts event, Emitter<PromptState> emit) async {
    await _subscription?.cancel();
    emit(PromptIdle());
    _subscription = watchActivePrompt().listen((prompt) {
      add(ActivePromptChanged(prompt));
    });
  }

  Future<void> _onStopWatching(
      StopWatchingPrompts event, Emitter<PromptState> emit) async {
    await _subscription?.cancel();
    emit(PromptIdle());
  }

  void _onActivePromptChanged(
      ActivePromptChanged event, Emitter<PromptState> emit) {
    emit(event.prompt == null ? PromptIdle() : PromptActive(event.prompt!));
  }

  void _onUseCandidate(
      UsePromptCandidateEvent event, Emitter<PromptState> emit) {
    resolvePrompt(event.id, event.candidate);
  }

  void _onServeEdited(
      ServeEditedPromptEvent event, Emitter<PromptState> emit) {
    resolvePromptEdited(event.id, statusCode: event.statusCode, body: event.body);
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}

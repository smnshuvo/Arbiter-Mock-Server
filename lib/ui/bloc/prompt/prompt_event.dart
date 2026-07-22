import 'package:equatable/equatable.dart';
import '../../../domain/entities/endpoint.dart';
import '../../../domain/entities/prompt.dart';

abstract class PromptEvent extends Equatable {
  const PromptEvent();

  @override
  List<Object?> get props => [];
}

class StartWatchingPrompts extends PromptEvent {}

class StopWatchingPrompts extends PromptEvent {}

class ActivePromptChanged extends PromptEvent {
  final PendingPrompt? prompt;

  const ActivePromptChanged(this.prompt);

  @override
  List<Object?> get props => [prompt];
}

class UsePromptCandidateEvent extends PromptEvent {
  final String id;
  final PromptCandidateResponse candidate;

  const UsePromptCandidateEvent(this.id, this.candidate);

  @override
  List<Object?> get props => [id, candidate];
}

class ServeEditedPromptEvent extends PromptEvent {
  final String id;
  final int statusCode;
  final String body;

  const ServeEditedPromptEvent(this.id, {required this.statusCode, required this.body});

  @override
  List<Object?> get props => [id, statusCode, body];
}

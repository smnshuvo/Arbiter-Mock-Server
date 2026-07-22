import 'package:equatable/equatable.dart';
import '../../../domain/entities/prompt.dart';

abstract class PromptState extends Equatable {
  const PromptState();

  @override
  List<Object?> get props => [];
}

class PromptInitial extends PromptState {}

/// No prompt currently needs the developer's attention.
class PromptIdle extends PromptState {}

/// [prompt] is shown to the developer now; anything behind it is queued.
class PromptActive extends PromptState {
  final PendingPrompt prompt;

  const PromptActive(this.prompt);

  @override
  List<Object?> get props => [prompt];
}

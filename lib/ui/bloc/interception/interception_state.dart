import 'package:equatable/equatable.dart';
import '../../../domain/entities/interception_request.dart';
import '../../../domain/entities/interception_mode.dart';

abstract class InterceptionState extends Equatable {
  const InterceptionState();

  @override
  List<Object?> get props => [];
}

class InterceptionInitial extends InterceptionState {}

class InterceptionEnabled extends InterceptionState {
  final InterceptionMode mode;
  final int timeoutSeconds;
  final List<String> whitelist;
  final UrlListMode urlListMode;

  const InterceptionEnabled({
    required this.mode,
    required this.timeoutSeconds,
    this.whitelist = const [],
    this.urlListMode = UrlListMode.whitelist,
  });

  @override
  List<Object?> get props => [mode, timeoutSeconds, whitelist, urlListMode];
}

class InterceptionDisabled extends InterceptionState {}

class InterceptionPending extends InterceptionState {
  final InterceptionRequest interception;
  final InterceptionMode mode;
  final int timeoutSeconds;
  final List<String> whitelist;
  final UrlListMode urlListMode;

  const InterceptionPending({
    required this.interception,
    required this.mode,
    required this.timeoutSeconds,
    this.whitelist = const [],
    this.urlListMode = UrlListMode.whitelist,
  });

  @override
  List<Object?> get props =>
      [interception, mode, timeoutSeconds, whitelist, urlListMode];
}

class InterceptionProcessing extends InterceptionState {
  final String id;

  const InterceptionProcessing(this.id);

  @override
  List<Object?> get props => [id];
}

class InterceptionCompleted extends InterceptionState {
  final String id;

  const InterceptionCompleted(this.id);

  @override
  List<Object?> get props => [id];
}

class InterceptionError extends InterceptionState {
  final String message;

  const InterceptionError(this.message);

  @override
  List<Object?> get props => [message];
}
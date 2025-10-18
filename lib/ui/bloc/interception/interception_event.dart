import 'package:equatable/equatable.dart';
import '../../../domain/entities/interception_request.dart';
import '../../../domain/entities/interception_mode.dart';

abstract class InterceptionEvent extends Equatable {
  const InterceptionEvent();

  @override
  List<Object?> get props => [];
}

class StartWatchingInterceptions extends InterceptionEvent {}

class StopWatchingInterceptions extends InterceptionEvent {}

class InterceptionReceived extends InterceptionEvent {
  final InterceptionRequest interception;

  const InterceptionReceived(this.interception);

  @override
  List<Object?> get props => [interception];
}

class ModifyAndContinueEvent extends InterceptionEvent {
  final String id;
  final String? method;
  final String? url;
  final Map<String, String>? headers;
  final String? body;
  final int? statusCode;

  const ModifyAndContinueEvent({
    required this.id,
    this.method,
    this.url,
    this.headers,
    this.body,
    this.statusCode,
  });

  @override
  List<Object?> get props => [id, method, url, headers, body, statusCode];
}

class ContinueWithoutModificationEvent extends InterceptionEvent {
  final String id;

  const ContinueWithoutModificationEvent(this.id);

  @override
  List<Object?> get props => [id];
}

class CancelInterceptionEvent extends InterceptionEvent {
  final String id;

  const CancelInterceptionEvent(this.id);

  @override
  List<Object?> get props => [id];
}

class SetInterceptionModeEvent extends InterceptionEvent {
  final InterceptionMode mode;

  const SetInterceptionModeEvent(this.mode);

  @override
  List<Object?> get props => [mode];
}

class GetInterceptionModeEvent extends InterceptionEvent {}

class SetInterceptionTimeoutEvent extends InterceptionEvent {
  final int seconds;

  const SetInterceptionTimeoutEvent(this.seconds);

  @override
  List<Object?> get props => [seconds];
}
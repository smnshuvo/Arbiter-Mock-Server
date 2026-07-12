import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/interception_mode.dart';
import '../../../domain/usecases/interception_usecases.dart';
import 'interception_event.dart';
import 'interception_state.dart';

class InterceptionBloc extends Bloc<InterceptionEvent, InterceptionState> {
  final WatchPendingInterceptions watchPendingInterceptions;
  final ModifyAndContinue modifyAndContinue;
  final ContinueWithoutModification continueWithoutModification;
  final CancelInterception cancelInterception;
  final SetInterceptionMode setInterceptionMode;
  final GetInterceptionMode getInterceptionMode;
  final SetInterceptionTimeout setInterceptionTimeout;
  final GetInterceptionTimeout getInterceptionTimeout;
  final SetInterceptionWhitelist setInterceptionWhitelist;
  final GetInterceptionWhitelist getInterceptionWhitelist;
  final SetUrlListMode setUrlListMode;
  final GetUrlListMode getUrlListMode;

  StreamSubscription? _interceptionSubscription;

  InterceptionBloc({
    required this.watchPendingInterceptions,
    required this.modifyAndContinue,
    required this.continueWithoutModification,
    required this.cancelInterception,
    required this.setInterceptionMode,
    required this.getInterceptionMode,
    required this.setInterceptionTimeout,
    required this.getInterceptionTimeout,
    required this.setInterceptionWhitelist,
    required this.getInterceptionWhitelist,
    required this.setUrlListMode,
    required this.getUrlListMode,
  }) : super(InterceptionInitial()) {
    on<StartWatchingInterceptions>(_onStartWatching);
    on<StopWatchingInterceptions>(_onStopWatching);
    on<InterceptionReceived>(_onInterceptionReceived);
    on<ModifyAndContinueEvent>(_onModifyAndContinue);
    on<ContinueWithoutModificationEvent>(_onContinueWithoutModification);
    on<CancelInterceptionEvent>(_onCancelInterception);
    on<SetInterceptionModeEvent>(_onSetInterceptionMode);
    on<GetInterceptionModeEvent>(_onGetInterceptionMode);
    on<SetInterceptionTimeoutEvent>(_onSetInterceptionTimeout);
    on<SetInterceptionWhitelistEvent>(_onSetInterceptionWhitelist);
    on<SetUrlListModeEvent>(_onSetUrlListMode);
  }

  InterceptionEnabled _enabledState(InterceptionMode mode, int timeout) {
    return InterceptionEnabled(
      mode: mode,
      timeoutSeconds: timeout,
      whitelist: getInterceptionWhitelist(),
      urlListMode: getUrlListMode(),
    );
  }

  Future<void> _onStartWatching(
      StartWatchingInterceptions event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      await _interceptionSubscription?.cancel();

      final mode = getInterceptionMode();
      final timeout = getInterceptionTimeout();

      if (mode == InterceptionMode.none) {
        emit(InterceptionDisabled());
      } else {
        emit(_enabledState(mode, timeout));
      }

      _interceptionSubscription = watchPendingInterceptions().listen(
            (interception) {
          add(InterceptionReceived(interception));
        },
        onError: (error) {
          add(InterceptionReceived(InterceptionReceived as dynamic));
        },
      );
    } catch (e) {
      emit(InterceptionError('Failed to start watching: $e'));
    }
  }

  Future<void> _onStopWatching(
      StopWatchingInterceptions event,
      Emitter<InterceptionState> emit,
      ) async {
    await _interceptionSubscription?.cancel();
    emit(InterceptionDisabled());
  }

  Future<void> _onInterceptionReceived(
      InterceptionReceived event,
      Emitter<InterceptionState> emit,
      ) async {
    final mode = getInterceptionMode();
    final timeout = getInterceptionTimeout();

    emit(InterceptionPending(
      interception: event.interception,
      mode: mode,
      timeoutSeconds: timeout,
      whitelist: getInterceptionWhitelist(),
      urlListMode: getUrlListMode(),
    ));
  }

  Future<void> _onModifyAndContinue(
      ModifyAndContinueEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      emit(InterceptionProcessing(event.id));

      await modifyAndContinue(
        event.id,
        method: event.method,
        url: event.url,
        headers: event.headers,
        body: event.body,
        statusCode: event.statusCode,
      );

      emit(InterceptionCompleted(event.id));

      // Return to enabled state
      final mode = getInterceptionMode();
      final timeout = getInterceptionTimeout();
      emit(_enabledState(mode, timeout));
    } catch (e) {
      emit(InterceptionError('Failed to modify and continue: $e'));
    }
  }

  Future<void> _onContinueWithoutModification(
      ContinueWithoutModificationEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      emit(InterceptionProcessing(event.id));

      await continueWithoutModification(event.id);

      emit(InterceptionCompleted(event.id));

      // Return to enabled state
      final mode = getInterceptionMode();
      final timeout = getInterceptionTimeout();
      emit(_enabledState(mode, timeout));
    } catch (e) {
      emit(InterceptionError('Failed to continue: $e'));
    }
  }

  Future<void> _onCancelInterception(
      CancelInterceptionEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      emit(InterceptionProcessing(event.id));

      await cancelInterception(event.id);

      emit(InterceptionCompleted(event.id));

      // Return to enabled state
      final mode = getInterceptionMode();
      final timeout = getInterceptionTimeout();
      emit(_enabledState(mode, timeout));
    } catch (e) {
      emit(InterceptionError('Failed to cancel: $e'));
    }
  }

  Future<void> _onSetInterceptionMode(
      SetInterceptionModeEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      await setInterceptionMode(event.mode);

      if (event.mode == InterceptionMode.none) {
        emit(InterceptionDisabled());
      } else {
        final timeout = getInterceptionTimeout();
        emit(_enabledState(event.mode, timeout));
      }
    } catch (e) {
      emit(InterceptionError('Failed to set mode: $e'));
    }
  }

  Future<void> _onGetInterceptionMode(
      GetInterceptionModeEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      final mode = getInterceptionMode();
      final timeout = getInterceptionTimeout();

      if (mode == InterceptionMode.none) {
        emit(InterceptionDisabled());
      } else {
        emit(_enabledState(mode, timeout));
      }
    } catch (e) {
      emit(InterceptionError('Failed to get mode: $e'));
    }
  }

  Future<void> _onSetInterceptionTimeout(
      SetInterceptionTimeoutEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      await setInterceptionTimeout(event.seconds);

      final mode = getInterceptionMode();
      if (mode != InterceptionMode.none) {
        emit(_enabledState(mode, event.seconds));
      }
    } catch (e) {
      emit(InterceptionError('Failed to set timeout: $e'));
    }
  }

  Future<void> _onSetInterceptionWhitelist(
      SetInterceptionWhitelistEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      await setInterceptionWhitelist(event.patterns);

      final mode = getInterceptionMode();
      if (mode != InterceptionMode.none) {
        final timeout = getInterceptionTimeout();
        emit(_enabledState(mode, timeout));
      }
    } catch (e) {
      emit(InterceptionError('Failed to set whitelist: $e'));
    }
  }

  Future<void> _onSetUrlListMode(
      SetUrlListModeEvent event,
      Emitter<InterceptionState> emit,
      ) async {
    try {
      await setUrlListMode(event.mode);

      final mode = getInterceptionMode();
      if (mode != InterceptionMode.none) {
        final timeout = getInterceptionTimeout();
        emit(_enabledState(mode, timeout));
      }
    } catch (e) {
      emit(InterceptionError('Failed to set URL list mode: $e'));
    }
  }

  @override
  Future<void> close() {
    _interceptionSubscription?.cancel();
    return super.close();
  }
}
